#include <stdio.h>
#include <stdint.h>
#include <unistd.h>
#include <fcntl.h>
#include <sys/mman.h>
#include <string.h>
#include <time.h>



#define VDMA_S2MM_CONTROL       0x30 / 4   // Control register
#define VDMA_S2MM_STATUS        0x34 / 4   // Status register
// #define VDMA_S2MM_INTR          0x38 / 4   // Interrupt status
#define VDMA_S2MM_INTR_MASK     0x3C / 4   // Interrupt mask
#define VDMA_S2MM_FRMDLY_STRIDE 0x58 / 4   // Frame delay & stride
// #define VDMA_S2MM_REG1          0x58 / 4   // Start address register 1
// #define VDMA_S2MM_REG2          0x5C / 4   // Start address register 2
// #define VDMA_S2MM_REG3          0x60 / 4   // Start address register 3
#define VDMA_S2MM_VSIZE         0x50 / 4   // Vertical size (lines)
#define VDMA_S2MM_HSIZE         0x54 / 4   // Horizontal size (pixels)

// Control register bits
#define VDMA_CTRL_RUN           (1 << 0)   // Start VDMA
#define VDMA_CTRL_CIRCULAR      (1 << 1)   // Circular buffering mode
#define VDMA_CTRL_RESET         (1 << 2)   // Reset
#define VDMA_CTRL_GENLOCK       (1 << 3)   // Genlock enable
#define VDMA_CTRL_FRAME_CNT_EN  (1 << 4)   // Frame count enable
#define VDMA_CTRL_DMA_IRQ_EN    (1 << 12)  // DMA interrupt enable

// Status register bits
#define VDMA_STAT_HALTED        (1 << 0)   // DMA halted
#define VDMA_STAT_ERROR         (1 << 14)   // Error

// Camera parameters
#define CAM_WIDTH       640
#define CAM_HEIGHT      480
#define CAM_BPP         2       // RGB565
#define FRAME_SIZE      (CAM_WIDTH * CAM_HEIGHT * CAM_BPP)

#define RAM_BUFFER_ADDR 0x0E000000
#define RAM_BUFFER_SIZE 0x00200000
#define NUM_FRAME_BUFFERS 3

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

void print_vdma_status(uint32_t status) {
    printf("VDMA Status: 0x%08x\n", status);
    if (status & VDMA_STAT_HALTED)   printf("  Halted: YES ⚠️\n");
    if (status & VDMA_STAT_IDLE)     printf("  Idle: YES\n");
    if (status & VDMA_STAT_SOF_IRQ)  printf("  Start of Frame IRQ: YES\n");
    if (status & VDMA_STAT_EOF_IRQ)  printf("  End of Frame IRQ: YES ✓\n");
    if (status & VDMA_STAT_ERROR)    printf("  Error: YES ⚠️\n");
}

uint64_t get_time_us(void) {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (uint64_t)ts.tv_sec * 1000000ULL + ts.tv_nsec / 1000ULL;
}

int main(int argc, char *argv[]) {
    int num_frames = 5;
    if (argc > 1) num_frames = atoi(argv[1]);

    // =====================================================
    // Open VDMA device
    // =====================================================
    int fd_uio = open("/dev/uio0", O_RDWR);  // VDMA is UIO0
    if (fd_uio < 0) {
        perror("Failed to open /dev/uio0 (VDMA)");
        return -1;
    }

    volatile uint32_t *vdma_regs = (volatile uint32_t *)mmap(NULL, 0x1000,
                                    PROT_READ | PROT_WRITE, MAP_SHARED, fd_uio, 0);
    if (vdma_regs == MAP_FAILED) {
        perror("Failed to mmap VDMA registers");
        close(fd_uio);
        return -1;
    }

    // =====================================================
    // Open video buffer memory
    // =====================================================
    int fd_mem = open("/dev/mem", O_RDWR | O_SYNC);
    if (fd_mem < 0) {
        perror("Failed to open /dev/mem");
        munmap((void *)vdma_regs, 0x1000);
        close(fd_uio);
        return -1;
    }

    volatile uint8_t *video_buf = (volatile uint8_t *)mmap(NULL, RAM_BUFFER_SIZE,
                                    PROT_READ | PROT_WRITE, MAP_SHARED, fd_mem, RAM_BUFFER_ADDR);
    if (video_buf == MAP_FAILED) {
        perror("Failed to mmap video buffer");
        munmap((void *)vdma_regs, 0x1000);
        close(fd_mem);
        close(fd_uio);
        return -1;
    }

    printf("=== VDMA Video Capture ===\n");
    printf("Resolution: %dx%d pixels (RGB565)\n", CAM_WIDTH, CAM_HEIGHT);
    printf("Frame size: %d bytes (%.2f MB)\n", FRAME_SIZE, FRAME_SIZE / (1024.0 * 1024.0));
    printf("Number of frame buffers: %d\n", NUM_FRAME_BUFFERS);
    printf("Buffer capacity: %.2f MB\n", RAM_BUFFER_SIZE / (1024.0 * 1024.0));
    printf("Capturing %d frames...\n\n", num_frames);

    // =====================================================
    // VDMA Configuration
    // =====================================================
    printf("Configuring VDMA...\n");

    // Stop VDMA first
    vdma_regs[VDMA_S2MM_CONTROL] = VDMA_CTRL_RESET;
    usleep(10000);

    // Configure frame size and stride
    // Note: Register layout may vary - adjust based on your IP core!
    // These are typical offsets for Xilinx VDMA
    
    uint32_t hsize = (CAM_WIDTH << 16) | CAM_WIDTH;  // Packed format
    uint32_t vsize = CAM_HEIGHT;
    uint32_t stride = CAM_WIDTH * CAM_BPP;  // Bytes per line

    vdma_regs[VDMA_S2MM_FRMDLY_STRIDE] = stride;

    // Configure frame buffer addresses (VDMA supports up to 3 buffers)
    uint32_t frame_addr_1 = RAM_BUFFER_ADDR;
    uint32_t frame_addr_2 = RAM_BUFFER_ADDR + FRAME_SIZE;
    uint32_t frame_addr_3 = RAM_BUFFER_ADDR + (2 * FRAME_SIZE);

    vdma_regs[VDMA_S2MM_REG1] = frame_addr_1;
    vdma_regs[VDMA_S2MM_REG2] = frame_addr_2;
    vdma_regs[VDMA_S2MM_REG3] = frame_addr_3;

    printf("  Frame buffer 1: 0x%08x\n", frame_addr_1);
    printf("  Frame buffer 2: 0x%08x\n", frame_addr_2);
    printf("  Frame buffer 3: 0x%08x\n", frame_addr_3);
    printf("  Stride: %d bytes/line\n", stride);
    printf("  Frame size: %d bytes\n", FRAME_SIZE);

    // Enable circular mode (for continuous capture)
    uint32_t ctrl = VDMA_CTRL_RUN | VDMA_CTRL_CIRCULAR | VDMA_CTRL_DMA_IRQ_EN;
    vdma_regs[VDMA_S2MM_CONTROL] = ctrl;

    printf("  VDMA control: 0x%08x\n", ctrl);
    printf("  VDMA configured! ✓\n\n");

    // =====================================================
    // Frame capture loop
    // =====================================================
    uint32_t unmask = 1;
    uint32_t irq_count;
    uint32_t frame_count = 0;
    uint64_t frame_start_time = 0;

    printf("Starting capture (waiting for EOF interrupts)...\n\n");

    while (frame_count < num_frames) {
        // Unmask interrupt
        write(fd_uio, &unmask, sizeof(unmask));

        if (frame_count == 0) {
            frame_start_time = get_time_us();
        }

        // Wait for End-of-Frame interrupt
        read(fd_uio, &irq_count, sizeof(irq_count));

        uint64_t now = get_time_us();
        uint32_t status = vdma_regs[VDMA_S2MM_STATUS];

        // Clear interrupt
        vdma_regs[VDMA_S2MM_INTR] = 0xF0000000;

        // Check status
        printf("Frame %d received\n", frame_count + 1);
        print_vdma_status(status);

        frame_count++;

        // Display sample data from captured frame
        uint32_t frame_offset = (frame_count % NUM_FRAME_BUFFERS) * FRAME_SIZE;
        volatile uint16_t *frame_data = (volatile uint16_t *)(video_buf + frame_offset);

        printf("  Frame data sample:\n");
        printf("    Top-left 5 pixels: ");
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
        printf("    Center [320,240]: RGB(%d,%d,%d) = 0x%04x\n", r, g, b, center_pixel);

        // Calculate frame rate
        if (frame_count > 0) {
            double elapsed_sec = (now - frame_start_time) / 1000000.0;
            double fps = frame_count / elapsed_sec;
            printf("    FPS: %.1f\n", fps);
        }

        printf("\n");
    }

    // =====================================================
    // Cleanup
    // =====================================================
    printf("=== Capture Complete ===\n");
    printf("Frames captured: %d\n", frame_count);

    // Stop VDMA
    vdma_regs[VDMA_S2MM_CONTROL] = 0;

    munmap((void *)video_buf, RAM_BUFFER_SIZE);
    munmap((void *)vdma_regs, 0x1000);
    close(fd_mem);
    close(fd_uio);

    printf("✅ Done!\n");

    return 0;
}
