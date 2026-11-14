#include <stdio.h>
#include <stdint.h>
#include <stdlib.h>
#include <unistd.h>
#include <fcntl.h>
#include <sys/mman.h>
#include <sys/time.h>
// #include <sys/socket.h>
#include <string.h>
#include <signal.h>
#include <errno.h>
#include <time.h>
#include <poll.h>


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


#define VIDEO_WIDTH     640
#define VIDEO_HEIGHT    480
#define VIDEO_BPP       2                                            // bytes per pixel
#define FRAME_SIZE      (VIDEO_WIDTH * VIDEO_HEIGHT * VIDEO_BPP)
#define NUM_BUFS        2
#define BUF_STRIDE      (1024*1024)   // 1MB
#define RESERVED_SIZE   (2*1024*1024) // 2MB
#define POLL_TIMEOUT_MS 100


_Static_assert(FRAME_SIZE <= BUF_STRIDE, "The frame size is greater than the stride between frames.");
_Static_assert(NUM_BUFS*BUF_STRIDE <= RESERVED_SIZE, "The reserved memory is less than the required memory for all frames.");


static volatile int g_running = 1;

static void sigint_handler(int sig)
{
    (void)sig;
    g_running = 0;
}

static double now_ms(void)
{
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return ts.tv_sec * 1000.0 + ts.tv_nsec / 1e6;
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
    uint32_t    buf_addr_base = (uint32_t)strtoul(argv[2], NULL, 0);
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

    volatile uint8_t *video_buf_base = mmap(NULL, NUM_BUFS*BUF_STRIDE,
        PROT_READ | PROT_WRITE, MAP_SHARED, fd_mem, buf_addr_base);
    if (video_buf_base == MAP_FAILED) {
        perror("mmap video buffer"); return -1;
    }


    dma_init(dma_regs);
    uio_drain(fd_uio);


    uint32_t unmask = 1;
    uint32_t irq_count;
    uint32_t frame_count = 0;
    size_t idx = 0;

    printf("[CAPTURE] %s -> %s buf=0x%08x\n", uio_dev, out_file, (uint32_t)(buf_addr_base+(idx%NUM_BUFS)*BUF_STRIDE));

    double t_prev = now_ms();
    double dt_min = 1e9, dt_max = 0, dt_sum = 0;
    uint32_t n_short = 0, len_min = FRAME_SIZE;


    dma_regs[S2MM_SR] = S2MM_SR_IOC_IRQ_CLR |
                        S2MM_SR_DLY_IRQ_CLR |
                        S2MM_SR_ERR_IRQ_CLR;
    dma_regs[S2MM_DA] = buf_addr_base;
    dma_regs[S2MM_LENGTH] = FRAME_SIZE;

    struct pollfd pfd;
    pfd.fd = fd_uio;    
    pfd.events = POLLIN;    
    pfd.revents = 0;

    while (g_running) {
    
        /* unmask interrupt */
        write(fd_uio, &unmask, sizeof(unmask));

        /* Wait for interrupt */
        int r = poll(&pfd, 1, POLL_TIMEOUT_MS);
        uint32_t status;
        uint32_t len;
        if (r < 0) {
            if (errno == EINTR) continue;
            perror("poll failed");
            break;
        } else if (r == 0) {
            // timeout

            status = dma_regs[S2MM_SR];
            len = dma_regs[S2MM_LENGTH];

            printf("[CAPTURE] %s DMA Error status=0x%08x  |  len %u\n", uio_dev, status, len);
            
            
            if (status & S2MM_SR_IOC_IRQ_CLR) {
                printf("[CAPTURE] %s lost UIO irq, recovering\n", uio_dev);
                dma_regs[S2MM_SR] = S2MM_SR_IOC_IRQ_CLR | S2MM_SR_DLY_IRQ_CLR | S2MM_SR_ERR_IRQ_CLR;
                dma_regs[S2MM_DA] = buf_addr_base+((++idx)%NUM_BUFS)*BUF_STRIDE;
                dma_regs[S2MM_LENGTH] = FRAME_SIZE;
            }
            
            if (status & (S2MM_SR_DEC_ERR | S2MM_SR_INT_ERR | S2MM_SR_SLV_ERR | S2MM_SR_HALTED)) {
                dma_init(dma_regs);
                uio_drain(fd_uio);
                dma_regs[S2MM_DA] = buf_addr_base+(idx%NUM_BUFS)*BUF_STRIDE;
                dma_regs[S2MM_LENGTH] = FRAME_SIZE;
            }
            continue;

        } else { // r > 0
            read(fd_uio, &irq_count, sizeof(irq_count));


            status = dma_regs[S2MM_SR];
            len = dma_regs[S2MM_LENGTH];
            dma_regs[S2MM_SR] = S2MM_SR_IOC_IRQ_CLR | S2MM_SR_DLY_IRQ_CLR | S2MM_SR_ERR_IRQ_CLR;
        
            if (status & (S2MM_SR_DEC_ERR | S2MM_SR_INT_ERR | S2MM_SR_SLV_ERR)) {
                printf("[CAPTURE] %s DMA Error status=0x%08x\n", uio_dev, status);
                dma_init(dma_regs);
                uio_drain(fd_uio);
                dma_regs[S2MM_DA] = buf_addr_base + ((idx)%NUM_BUFS)*BUF_STRIDE;
                dma_regs[S2MM_LENGTH] = FRAME_SIZE;
                continue;
            }
        }

        dma_regs[S2MM_DA] = buf_addr_base + ((idx+1)%NUM_BUFS)*BUF_STRIDE;
        dma_regs[S2MM_LENGTH] = FRAME_SIZE;

    
        double t = now_ms();
        double dt = t - t_prev;
        t_prev = t;

        if (dt < dt_min) dt_min = dt;
        if (dt > dt_max) dt_max = dt;
        dt_sum += dt;
        if (len != FRAME_SIZE) n_short++;
        if (len < len_min) len_min = len;

        frame_count++;
        if (len == FRAME_SIZE)
        {
            char tmp_path[256];
            snprintf(tmp_path, sizeof(tmp_path), "%s.tmp", out_file);

            int fd_out = open(tmp_path, O_WRONLY | O_CREAT | O_TRUNC, 0644);
            if (fd_out >= 0) {
                size_t n = write(fd_out, (const void *)(video_buf_base+(idx%NUM_BUFS)*BUF_STRIDE), FRAME_SIZE);
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
    }

        if (frame_count % 30 == 0) {
            printf("[CAPTURE] %s %u frames | dt avg %.1f min %.1f max %.1f ms | short %u/30, min len %u\n",
                uio_dev, frame_count, dt_sum / 30, dt_min, dt_max, n_short, len_min);
            dt_min = 1e9; 
            dt_max = 0; 
            dt_sum = 0;
            n_short = 0; 
            len_min = FRAME_SIZE;
        }
        idx = (idx + 1) % NUM_BUFS;
    }

    printf("\n[CAPTURE] %s stopped. Total: %u frames\n", uio_dev, frame_count);
    return 0;
}

