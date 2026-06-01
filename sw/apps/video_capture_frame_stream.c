#include <stdio.h>
#include <stdint.h>
#include <stdlib.h>
#include <unistd.h>
#include <fcntl.h>
#include <sys/mman.h>
#include <string.h>
#include <signal.h>

#define S2MM_CR      (0x30 / 4)
#define S2MM_SR      (0x34 / 4)
#define S2MM_DA      (0x48 / 4)
#define S2MM_LENGTH  (0x58 / 4)

#define S2MM_CR_RUN_STOP    (1 << 0)
#define S2MM_CR_IOC_IRQ_EN  (1 << 12)
#define S2MM_CR_SOFT_RST    (1 << 2)

#define S2MM_SR_INT_ERR     (1 << 4)
#define S2MM_SR_SLV_ERR     (1 << 5)
#define S2MM_SR_DEC_ERR     (1 << 6)

#define S2MM_SR_IOC_IRQ_CLR (1 << 12)
#define S2MM_SR_DLY_IRQ_CLR (1 << 13)
#define S2MM_SR_ERR_IRQ_CLR (1 << 14)

#define CAM_WIDTH       640
#define CAM_HEIGHT      480
#define CAM_BPP         2
#define FRAME_SIZE      (CAM_WIDTH * CAM_HEIGHT * CAM_BPP)

#define RAM_BUFFER_ADDR 0x0E000000
#define RAM_BUFFER_SIZE 0x00200000

#define SHM_FRAME_TMP   "/dev/shm/frame_next.raw"
#define SHM_FRAME       "/dev/shm/frame.raw"

static volatile int g_running = 1;

static void sigint_handler(int sig)
{
    (void)sig;
    g_running = 0;
}

int main()
{
    signal(SIGINT, sigint_handler);

    int fd_uio = open("/dev/uio0", O_RDWR);
    if (fd_uio < 0) { perror("open /dev/uio0"); return -1; }

    volatile uint32_t *dma_regs = mmap(NULL, 0x1000,
        PROT_READ | PROT_WRITE, MAP_SHARED, fd_uio, 0);
    if (dma_regs == MAP_FAILED) {
        perror("mmap DMA regs"); close(fd_uio); return -1;
    }

    int fd_mem = open("/dev/mem", O_RDWR | O_SYNC);
    if (fd_mem < 0) {
        perror("open /dev/mem");
        munmap((void *)dma_regs, 0x1000); close(fd_uio); return -1;
    }

    volatile uint8_t *video_buf = mmap(NULL, RAM_BUFFER_SIZE,
        PROT_READ | PROT_WRITE, MAP_SHARED, fd_mem, RAM_BUFFER_ADDR);
    if (video_buf == MAP_FAILED) {
        perror("mmap video buffer");
        munmap((void *)dma_regs, 0x1000); close(fd_mem); close(fd_uio);
        return -1;
    }

    dma_regs[S2MM_CR] = S2MM_CR_RUN_STOP | S2MM_CR_IOC_IRQ_EN;

    uint32_t unmask = 1;
    uint32_t irq_count;
    uint32_t frame_count = 0;

    printf("[CAPTURE] Streaming to %s\n", SHM_FRAME);
    printf("[CAPTURE] %dx%d  %u bytes/frame\n\n",
           CAM_WIDTH, CAM_HEIGHT, FRAME_SIZE);

    while (g_running) {
        write(fd_uio, &unmask, sizeof(unmask));
        dma_regs[S2MM_DA] = RAM_BUFFER_ADDR;
        dma_regs[S2MM_LENGTH] = FRAME_SIZE;

        read(fd_uio, &irq_count, sizeof(irq_count));

        uint32_t status = dma_regs[S2MM_SR];
        dma_regs[S2MM_SR] = S2MM_SR_IOC_IRQ_CLR |
                            S2MM_SR_DLY_IRQ_CLR |
                            S2MM_SR_ERR_IRQ_CLR;

        if (status & (S2MM_SR_DEC_ERR | S2MM_SR_INT_ERR | S2MM_SR_SLV_ERR)) {
            printf("[CAPTURE] DMA Error status=0x%08x\n", status);
            dma_regs[S2MM_CR] = S2MM_CR_SOFT_RST;
            while (dma_regs[S2MM_CR] & S2MM_CR_SOFT_RST);
            dma_regs[S2MM_CR] = S2MM_CR_RUN_STOP | S2MM_CR_IOC_IRQ_EN;
            continue;
        }

        frame_count++;

        /* Atomic handoff via rename() */
        int fd_out = open(SHM_FRAME_TMP,
                          O_WRONLY | O_CREAT | O_TRUNC, 0644);
        if (fd_out >= 0) {
            ssize_t n = write(fd_out, (const void *)video_buf, FRAME_SIZE);
            if (n == FRAME_SIZE) {
                fsync(fd_out);
                close(fd_out);
                rename(SHM_FRAME_TMP, SHM_FRAME);
            } else {
                close(fd_out);
                perror("write frame");
            }
        } else {
            perror("open shm tmp");
        }

        if (frame_count % 30 == 0)
            printf("[CAPTURE] %u frames\n", frame_count);
    }

    printf("\n[CAPTURE] Stopped. Total: %u frames\n", frame_count);

    munmap((void *)video_buf, RAM_BUFFER_SIZE);
    munmap((void *)dma_regs, 0x1000);
    close(fd_mem);
    close(fd_uio);
    return 0;
}
