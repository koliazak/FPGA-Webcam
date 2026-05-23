#include <stdio.h>
#include <stdint.h>
#include <unistd.h>
#include <fcntl.h>
#include <sys/mman.h>
#include <string.h>

// AXI DMA S2MM
#define S2MM_CR      0x30 / 4   // Control Register
#define S2MM_SR      0x34 / 4   // Status Register
#define S2MM_DA      0x48 / 4   // Destination Address
#define S2MM_LENGTH  0x58 / 4   // Transfer Length

// OV7670 camera parameters
#define CAM_WIDTH       640
#define CAM_HEIGHT      480
#define CAM_BPP         2       // Bytes per pixel (RGB565)
#define ROW_SIZE        (CAM_WIDTH * CAM_BPP)  // 1,280 bytes per row
#define FRAME_SIZE      (CAM_WIDTH * CAM_HEIGHT * CAM_BPP)

#define RAM_BUFFER_ADDR 0x0FE00000 // See system-user.dtsi
#define RAM_BUFFER_SIZE 0x00200000

typedef struct {
    uint16_t r : 5;
    uint16_t g : 6;
    uint16_t b : 5;
} RGB565;

void rgb565_to_rgb(uint16_t pixel, uint8_t *r, uint8_t *g, uint8_t *b) {
    RGB565 *p = (RGB565 *)&pixel;
    *r = (p->r << 3) | (p->r >> 2);
    *g = (p->g << 2) | (p->g >> 4);
    *b = (p->b << 3) | (p->b >> 2);
}

int main() {
    int fd_uio = open("/dev/uio0", O_RDWR);
    if (fd_uio < 0) {
        perror("Failed to open /dev/uio0");
        return -1;
    }
    
    volatile uint32_t *dma_regs = (volatile uint32_t *)mmap(NULL, 0x1000, 
                                   PROT_READ | PROT_WRITE, MAP_SHARED, fd_uio, 0);
    if (dma_regs == MAP_FAILED) {
        perror("Failed to mmap DMA registers");
        close(fd_uio);
        return -1;
    }

    int fd_mem = open("/dev/mem", O_RDWR | O_SYNC);
    if (fd_mem < 0) {
        perror("Failed to open /dev/mem");
        munmap((void *)dma_regs, 0x1000);
        close(fd_uio);
        return -1;
    }
    
    volatile uint8_t *video_buf = (volatile uint8_t *)mmap(NULL, RAM_BUFFER_SIZE, 
                                   PROT_READ | PROT_WRITE, MAP_SHARED, fd_mem, RAM_BUFFER_ADDR);
    if (video_buf == MAP_FAILED) {
        perror("Failed to mmap video buffer");
        munmap((void *)dma_regs, 0x1000);
        close(fd_mem);
        close(fd_uio);
        return -1;
    }

    printf("=== OV7670 Video Capture (Row-wise) ===\n");
    printf("Frame size: %dx%d\n", CAM_WIDTH, CAM_HEIGHT);
    printf("Row size: %d bytes\n", ROW_SIZE);
    printf("Interrupts per frame: %d (one per row)\n", CAM_HEIGHT);
    printf("Capturing 2 complete frames...\n\n");

    // Initialize DMA
    dma_regs[S2MM_CR] = 0x1001;          // Run + IOC_IrqEn
    dma_regs[S2MM_DA] = RAM_BUFFER_ADDR;

    uint32_t unmask = 1;
    uint32_t irq_count;
    uint32_t frame_count = 0;
    uint32_t row_count = 0;
    uint32_t current_buffer_offset = 0;
    int frame_started = 0;

    while (frame_count < 2) {
        write(fd_uio, &unmask, sizeof(unmask));

        // Start DMA for one row
        dma_regs[S2MM_LENGTH] = ROW_SIZE;

        // Wait for row interrupt
        read(fd_uio, &irq_count, sizeof(irq_count));

        uint32_t status = dma_regs[S2MM_SR];

        // Clear interrupt status
        dma_regs[S2MM_SR] = 0x7000;

        // Check for errors
        if (status & 0x00000001) {
            printf("ERROR: DMA Halted! Status = 0x%08x\n", status);
            
            // Reset DMA
            dma_regs[S2MM_CR] = 0x0004;
            while(dma_regs[S2MM_CR] & 0x0004);
            
            // Restart
            dma_regs[S2MM_CR] = 0x1001;
            dma_regs[S2MM_DA] = RAM_BUFFER_ADDR + current_buffer_offset;
            continue;
        }

        row_count++;

        // Frame start detection by counting 480 rows
        // TODO: use tuser for this purpose 
        if (!frame_started) {
            printf("Frame %d started\n", frame_count + 1);
            frame_started = 1;
        }

        // Print progress every 100 rows
        if (row_count % 100 == 0) {
            printf("  Received %d rows (%.1f%% of frame)\n", row_count, (100.0 * (row_count % CAM_HEIGHT) / CAM_HEIGHT));
        }

        // Check if frame is complete
        if (row_count % CAM_HEIGHT == 0) {
            frame_count++;
            uint32_t frame_buffer_offset = (frame_count - 1) * FRAME_SIZE;
            volatile uint16_t *frame_data = (volatile uint16_t *)(video_buf + frame_buffer_offset);
            
            printf("\nFrame %d COMPLETE (received %d rows)\n", frame_count, CAM_HEIGHT);

            // Display sample data from completed frame
            printf("  Top-left corner (first 5 pixels of first row):\n    ");
            for (int i = 0; i < 5; i++) {
                uint16_t pixel = frame_data[i];
                uint8_t r, g, b;
                rgb565_to_rgb(pixel, &r, &g, &b);
                printf("[%02x%02x%02x] ", r, g, b);
            }
            printf("\n");

            // Center pixel
            uint32_t center_idx = (CAM_HEIGHT / 2) * CAM_WIDTH + (CAM_WIDTH / 2);
            uint16_t center_pixel = frame_data[center_idx];
            uint8_t r, g, b;
            rgb565_to_rgb(center_pixel, &r, &g, &b);
            printf("  Center pixel [320,240]: RGB(%d, %d, %d) = 0x%04x\n", 
                   r, g, b, center_pixel);

            // Last row sample
            printf("  Last row [479] first pixels:\n    ");
            uint32_t last_row_start = (CAM_HEIGHT - 1) * CAM_WIDTH;
            for (int i = 0; i < 5; i++) {
                uint16_t pixel = frame_data[last_row_start + i];
                rgb565_to_rgb(pixel, &r, &g, &b);
                printf("[%02x%02x%02x] ", r, g, b);
            }
            printf("\n\n");

            // Setup for next frame
            if (frame_count < 2) {
                current_buffer_offset = frame_count * FRAME_SIZE;
                dma_regs[S2MM_DA] = RAM_BUFFER_ADDR + current_buffer_offset;
                frame_started = 0;
            }
        } else {
            // Setup DMA for next row in current frame
            current_buffer_offset += ROW_SIZE;
            dma_regs[S2MM_DA] = RAM_BUFFER_ADDR + current_buffer_offset;
        }
    }

    printf("=== Capture Complete ===\n");
    printf("Total rows received: %d\n", row_count);
    printf("Complete frames: %d\n", frame_count);

    // Cleanup
    munmap((void *)video_buf, RAM_BUFFER_SIZE);
    munmap((void *)dma_regs, 0x1000);
    close(fd_mem);
    close(fd_uio);

    return 0;
}
