#include <stdio.h>
#include <stdint.h>
#include <stdlib.h>
#include <unistd.h>
#include <fcntl.h>
#include <sys/mman.h>
#include <sys/time.h>
#include <sys/socket.h>
#include <string.h>
#include <signal.h>
#include <errno.h>

#define S2MM_CR      (0x30 / 4)
#define S2MM_SR      (0x34 / 4)
#define S2MM_DA      (0x48 / 4)
#define S2MM_LENGTH  (0x58 / 4)

#define S2MM_CR_RUN_STOP    (1 << 0)
#define S2MM_CR_IOC_IRQ_EN  (1 << 12)
#define S2MM_CR_SOFT_RST    (1 << 2)

#define S2MM_SR_HALTED      (1 << 0)
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

static volatile int g_running = 1;

static void sigint_handler(int sig)
{
    (void)sig;
    g_running = 0;
}

static void uio_drain(int fd_uio)
{
    uint32_t dummy;
    uint32_t unmask = 1;
    write(fd_uio, &unmask, sizeof(unmask));
    int flags = fcntl(fd_uio, F_GETFL, 0);
    fcntl(fd_uio, F_SETFL, flags | O_NONBLOCK);
    while (read(fd_uio, &dummy, sizeof(dummy)) > 0) { }
    fcntl(fd_uio, F_SETFL, flags);
}

static void dma_init(volatile uint32_t *dma_regs)
{
    dma_regs[S2MM_CR] = 0;
    int t = 1000;
    while ((dma_regs[S2MM_SR] & S2MM_SR_HALTED) == 0 && --t)
        usleep(10);

    dma_regs[S2MM_CR] = S2MM_CR_SOFT_RST;
    t = 1000;
    while ((dma_regs[S2MM_CR] & S2MM_CR_SOFT_RST) && --t)
        usleep(10);

    dma_regs[S2MM_SR] = S2MM_SR_IOC_IRQ_CLR |
                        S2MM_SR_DLY_IRQ_CLR |
                        S2MM_SR_ERR_IRQ_CLR;

    dma_regs[S2MM_CR] = S2MM_CR_RUN_STOP | S2MM_CR_IOC_IRQ_EN;
}

int main(int argc, char **argv)
{
    if (argc < 4) {
        fprintf(stderr, "Usage: %s <uio_dev> <buf_addr_hex> <out_file>\n", argv[0]);
        fprintf(stderr, "Example: %s /dev/uio0 0x0E000000 /dev/shm/frame_l.raw\n", argv[0]);
        return 1;
    }

    const char *uio_dev  = argv[1];
    uint32_t    buf_addr = (uint32_t)strtoul(argv[2], NULL, 0);
    const char *out_file = argv[3];

    signal(SIGINT, sigint_handler);

    int fd_uio = open(uio_dev, O_RDWR);
    if (fd_uio < 0) { perror("open uio"); return -1; }

    volatile uint32_t *dma_regs = mmap(NULL, 0x1000,
        PROT_READ | PROT_WRITE, MAP_SHARED, fd_uio, 0);
    if (dma_regs == MAP_FAILED) {
        perror("mmap DMA regs"); close(fd_uio); return -1;
    }

    int fd_mem = open("/dev/mem", O_RDWR | O_SYNC);
    if (fd_mem < 0) { perror("open /dev/mem"); return -1; }

    volatile uint8_t *video_buf = mmap(NULL, FRAME_SIZE,
        PROT_READ | PROT_WRITE, MAP_SHARED, fd_mem, buf_addr);
    if (video_buf == MAP_FAILED) {
        perror("mmap video buffer"); return -1;
    }

    dma_init(dma_regs);
    uio_drain(fd_uio);

    struct timeval tv = { .tv_sec = 2, .tv_usec = 0 };
    setsockopt(fd_uio, SOL_SOCKET, SO_RCVTIMEO, &tv, sizeof(tv));

    uint32_t unmask = 1;
    uint32_t irq_count;
    uint32_t frame_count = 0;

    printf("[CAPTURE] %s -> %s buf=0x%08x\n", uio_dev, out_file, buf_addr);

    while (g_running) {
        /* Arm DMA first */
        dma_regs[S2MM_DA] = buf_addr;
        dma_regs[S2MM_LENGTH] = FRAME_SIZE;

        /* Clear any leftover status before unmasking */
        dma_regs[S2MM_SR] = S2MM_SR_IOC_IRQ_CLR |
                            S2MM_SR_DLY_IRQ_CLR |
                            S2MM_SR_ERR_IRQ_CLR;

        /* Now unmask interrupt */
        write(fd_uio, &unmask, sizeof(unmask));

        /* Wait for interrupt */
        if (read(fd_uio, &irq_count, sizeof(irq_count)) < 0) {
            if (errno == EINTR) continue;
            if (errno == EAGAIN || errno == EWOULDBLOCK) {
                uint32_t status = dma_regs[S2MM_SR];
                if (status & S2MM_SR_IOC_IRQ_CLR) {
                    printf("[CAPTURE] %s lost UIO irq, recovering\n", uio_dev);
                    continue;
                }
            }
            perror("read uio");
            break;
        }

        uint32_t status = dma_regs[S2MM_SR];
        dma_regs[S2MM_SR] = S2MM_SR_IOC_IRQ_CLR |
                            S2MM_SR_DLY_IRQ_CLR |
                            S2MM_SR_ERR_IRQ_CLR;

        if (status & (S2MM_SR_DEC_ERR | S2MM_SR_INT_ERR | S2MM_SR_SLV_ERR)) {
            printf("[CAPTURE] %s DMA Error status=0x%08x\n", uio_dev, status);
            dma_init(dma_regs);
            uio_drain(fd_uio);
            continue;
        }

        frame_count++;

        char tmp_path[256];
        snprintf(tmp_path, sizeof(tmp_path), "%s.tmp", out_file);

        int fd_out = open(tmp_path, O_WRONLY | O_CREAT | O_TRUNC, 0644);
        if (fd_out >= 0) {
            ssize_t n = write(fd_out, (const void *)video_buf, FRAME_SIZE);
            if (n == FRAME_SIZE) {
                fsync(fd_out);
                close(fd_out);
                rename(tmp_path, out_file);
            } else {
                close(fd_out);
                perror("write frame");
            }
        } else {
            perror("open tmp");
        }

        if (frame_count % 30 == 0)
            printf("[CAPTURE] %s %u frames\n", uio_dev, frame_count);
    }

    printf("\n[CAPTURE] %s stopped. Total: %u frames\n", uio_dev, frame_count);
    return 0;
}

