#ifndef PCFX_H
#define PCFX_H

#define PCFX_SECTOR_LEN 2352
#define PCFX_BUFFER_SIZE PCFX_SECTOR_LEN

void pcfx_mount_cd(int s_index, const char *filename);
// void pcfx_fill_blanksave(uint8_t *buffer, uint32_t lba, int cnt);
void pcfx_read_cd(uint8_t *buffer, int lba, int cnt);
int pcfx_chd_hunksize();
void pcfx_poll();
// void pcfx_load_root_nvram();
int pcfx_get_img_size();

#endif
