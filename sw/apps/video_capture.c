#include <stdio.h>
#include <stdint.h>
#include <unistd.h>
#include <fcntl.h>
#include <sys/mman.h>
#include <string.h>

// AXI DMA (S2MM) register offsets
#define S2MM_CR      0x30 / 4   // Control Register
#define S2MM_SR      0x34 / 4   // Status Register
#define S2MM_DA      0x48 / 4   // Destination Address
#define S2MM_LENGTH  0x58 / 4   // Transfer Length

// AXI DMA (S2MM) register values
#define S2MM_CR_RUN_STOP    (1 << 0)
#define S2MM_CR_IOC_IRQ_EN  (1 << 12)
#define S2MM_CR_SOFT_RST    (1 << 2)


#define S2MM_SR_INT_ERR     (1 << 4)
#define S2MM_SR_SLV_ERR     (1 << 5)
#define S2MM_SR_DEC_ERR     (1 << 6)

#define S2MM_SR_IOC_IRQ_CLR (1 << 12)
#define S2MM_SR_DLY_IRQ_CLR (1 << 13)
#define S2MM_SR_ERR_IRQ_CLR (1 << 14)



// OV7670 camera parameters
#define CAM_WIDTH       640
#define CAM_HEIGHT      480
#define CAM_BPP         2       // Bytes per pixel (RGB565)
#define ROW_SIZE        (CAM_WIDTH * CAM_BPP)  // 1,280 bytes per row
#define FRAME_SIZE      (CAM_WIDTH * CAM_HEIGHT * CAM_BPP)

#define RAM_BUFFER_ADDR 0x0E000000
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

// PPM
void save_frame_ppm(const char *filename, const volatile uint16_t *rgb565, int w, int h)
{
    FILE *f = fopen(filename, "wb");
    if (!f) { perror("fopen"); return; }

    fprintf(f, "P6\n%d %d\n255\n", w, h);

    for (int y = 0; y < h; y++) {
        for (int x = 0; x < w; x++) {
            uint16_t p = rgb565[y * w + x];
            uint8_t r = ((p >> 11) & 0x1F) << 3;
            uint8_t g = ((p >> 5)  & 0x3F) << 2;
            uint8_t b = ((p >> 0)  & 0x1F) << 3;
            uint8_t pix[3] = {r, g, b};
            fwrite(pix, 1, 3, f);
        }
    }
    fclose(f);
    printf("Saved %s\n", filename);
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


    printf("Capturing 2 complete frames (Full Frame Mode)...\n\n");

    // Initialize DMA
    dma_regs[S2MM_CR] = S2MM_CR_RUN_STOP | S2MM_CR_IOC_IRQ_EN;

    uint32_t unmask = 1;
    uint32_t irq_count;
    uint32_t frame_count = 0;

    while (frame_count < 2) {
        // Unmask UIO interrupt
        write(fd_uio, &unmask, sizeof(unmask));

        printf("Frame %d started...\n", frame_count + 1);

        // Set destination address for the frame
        uint32_t current_buffer_offset = frame_count * FRAME_SIZE;
        dma_regs[S2MM_DA] = RAM_BUFFER_ADDR + current_buffer_offset;

        // Start DMA for the whole frame 
        // FRAME_SIZE must be 640 * 480 * 2 = 614400 bytes
        dma_regs[S2MM_LENGTH] = FRAME_SIZE; 

        // Wait for frame interrupt (will trigger when TLAST is received)
        read(fd_uio, &irq_count, sizeof(irq_count));

        uint32_t status = dma_regs[S2MM_SR];

        // Clear interrupt status
        dma_regs[S2MM_SR] = S2MM_SR_IOC_IRQ_CLR | S2MM_SR_DLY_IRQ_CLR | S2MM_SR_ERR_IRQ_CLR;

        // Check for errors
        if (status & (S2MM_SR_DEC_ERR | S2MM_SR_INT_ERR | S2MM_SR_SLV_ERR)) {
            printf("ERROR: DMA Halted! Status = 0x%08x\n", status);
            // Reset DMA
            dma_regs[S2MM_CR] = S2MM_CR_SOFT_RST;
            while(dma_regs[S2MM_CR] & S2MM_CR_SOFT_RST);
            dma_regs[S2MM_CR] = S2MM_CR_RUN_STOP | S2MM_CR_IOC_IRQ_EN;
            continue;
        }

        frame_count++;

        volatile uint16_t *frame_data = (volatile uint16_t *)(video_buf + current_buffer_offset);
        
        char filename[32];
        sprintf(filename, "/tmp/frame%d.ppm", frame_count);
        save_frame_ppm(filename, frame_data, CAM_WIDTH, CAM_HEIGHT);
        
        printf("Frame %d COMPLETE (received %d bytes)\n", frame_count, FRAME_SIZE);
    }

    munmap((void *)video_buf, RAM_BUFFER_SIZE);
    munmap((void *)dma_regs, 0x1000);
    close(fd_mem);
    close(fd_uio);

    return 0;
}

