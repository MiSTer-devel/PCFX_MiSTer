
#include <cstddef>
#include <cstdint>
#include <functional>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <array>
#include <assert.h>
#include <inttypes.h>
#include <memory>

#include "../../file_io.h"
//#include "../../user_io.h"
//#include "../../spi.h"
//#include "../../hardware.h"
//#include "../../menu.h"
#include "pcfx.h"
#include "../../cd.h"
#include "../chd/mister_chd.h"
#include <libchdr/chd.h>
//#include <arpa/inet.h>

struct toc_entry
{
	uint8_t control;
	uint8_t track;
	uint8_t m;
	uint8_t s;
	uint8_t f;
};

struct read_toc {
    uint16_t length;
    uint8_t first_track_num;
    uint8_t last_track_num;
    struct {
        uint8_t res0;
        uint8_t adr_control;
        uint8_t track_number;
        uint8_t res1;
        uint8_t zero;
        uint8_t mins;
        uint8_t secs;
        uint8_t frac;
    } track_desc[100];
};

static std::array<struct toc_entry, 200> toc_buffer;
static uint32_t toc_entry_count = 0;

static uint8_t* chd_hunkbuf = NULL;
static int chd_hunknum;
static toc_t toc = {};
static int pcfx_img_size;

static int sgets(char* out, int sz, char** in)
{
	*out = 0;
	do
	{
		char* instr = *in;
		int cnt = 0;

		while (*instr && *instr != 10)
		{
			if (*instr == 13)
			{
				instr++;
				continue;
			}

			if (cnt < sz - 1)
			{
				out[cnt++] = *instr;
				out[cnt] = 0;
			}

			instr++;
		}

		if (*instr == 10)
			instr++;
		*in = instr;
	} while (!*out && **in);

	return *out;
}

static void unload_chd(toc_t* table)
{
	if (table->chd_f)
	{
		chd_close(table->chd_f);
	}
	if (chd_hunkbuf)
		free(chd_hunkbuf);
	memset(table, 0, sizeof(toc_t));
	chd_hunknum = -1;
}

static void unload_cue(toc_t* table)
{
	for (int i = 0; i < table->last; i++)
	{
		FileClose(&table->tracks[i].f);
	}

	memset(table, 0, sizeof(toc_t));
}

static int load_chd(const char* filename, toc_t* table)
{
	unload_chd(table);
	chd_error err = mister_load_chd(filename, table);
	if (err != CHDERR_NONE)
	{
		return 0;
	}

	for (int i = 0; i < table->last; i++)
	{
		table->tracks[i].pregap = table->tracks[i].indexes[1];
        table->tracks[i].end -= 1;

		printf("\x1b[32mCHD: Track = %u, start = %u, end = %u, offset = %d, sector_size=%d, type = %u, pregap = "
			   "%u\n\x1b[0m",
			   i,
			   table->tracks[i].start,
			   table->tracks[i].end,
			   table->tracks[i].offset,
			   table->tracks[i].sector_size,
			   table->tracks[i].type,
			   table->tracks[i].pregap);
	}

	chd_hunkbuf = (uint8_t*)malloc(table->chd_hunksize);
	chd_hunknum = -1;

	return 1;
}

static int load_cue(const char* filename, toc_t* table)
{
	static char fname[1024 + 10];
	static char line[128];
	char *ptr, *lptr;
	static char cue[100 * 1024];

	unload_cue(table);
	strcpy(fname, filename);
	printf("\x1b[32mPCFX: Open CUE: %s\n\x1b[0m", fname);

	memset(cue, 0, sizeof(cue));
	if (!FileLoad(fname, cue, sizeof(cue) - 1))
	{
		printf("\x1b[32mPCFX: cannot load file: %s\n\x1b[0m", fname);
		return 0;
	}

	int mm, ss, bb;
	int index0 = 0;
	int index1 = 0;

	char* buf = cue;
	while (sgets(line, sizeof(line), &buf))
	{
		lptr = line;
		while (*lptr == 0x20)
			lptr++;

		/* decode FILE commands */
		if (!(memcmp(lptr, "FILE", 4)))
		{
			ptr = fname + strlen(fname) - 1;
			while ((ptr - fname) && (*ptr != '/') && (*ptr != '\\'))
				ptr--;
			if (ptr - fname)
				ptr++;

			lptr += 4;
			while (*lptr == 0x20)
				lptr++;

			if (*lptr == '\"')
			{
				lptr++;
				while ((*lptr != '\"') && (lptr <= (line + 128)) && (ptr < (fname + 1023)))
					*ptr++ = *lptr++;
			}
			else
			{
				while ((*lptr != 0x20) && (lptr <= (line + 128)) && (ptr < (fname + 1023)))
					*ptr++ = *lptr++;
			}
			*ptr = 0;

			if (!FileOpen(&table->tracks[table->last].f, fname))
				return 0;

			printf("\x1b[32mPCFX: Open track file: %s\n\x1b[0m", fname);

			table->tracks[table->last].offset = 0;

			if (!strstr(lptr, "BINARY"))
			{
				FileClose(&table->tracks[table->last].f);
				printf("\x1b[32mPCFX: unsupported file: %s\n\x1b[0m", fname);
				return 0;
			}
		}

		/* decode PREGAP commands */
		else if (sscanf(lptr, "PREGAP %02d:%02d:%02d", &mm, &ss, &bb) == 3)
		{
			// TODO Find an example image
		}
		/* decode TRACK commands */
		else if ((sscanf(lptr, "TRACK %02d %*s", &bb)) || (sscanf(lptr, "TRACK %d %*s", &bb)))
		{
			index0 = 0;
			if (bb != (table->last + 1))
			{
				FileClose(&table->tracks[table->last].f);
				printf("\x1b[32mPCFX: missing tracks: %s\n\x1b[0m", fname);
				return 0;
			}
			bool mode1{strstr(lptr, "MODE1/2352") != nullptr};
			bool mode2{strstr(lptr, "MODE2/2352") != nullptr};
			bool audio{strstr(lptr, "AUDIO") != nullptr};

			table->tracks[table->last].sector_size = PCFX_SECTOR_LEN;

			if (mode1)
				table->tracks[table->last].type = TT_MODE1;
			else if (mode2)
				table->tracks[table->last].type = TT_MODE2;
			else if (audio)
				table->tracks[table->last].type = TT_CDDA;
			else
			{
				FileClose(&table->tracks[table->last].f);
				printf("\x1b[32mPCFX: unsupported track type: %s\n\x1b[0m", lptr);
				return 0;
			}
		}

		/* decode INDEX commands */
		else if ((sscanf(lptr, "INDEX 00 %02d:%02d:%02d", &mm, &ss, &bb) == 3) ||
				 (sscanf(lptr, "INDEX 0 %02d:%02d:%02d", &mm, &ss, &bb) == 3))
		{
			index0 = bb + ss * 75 + mm * 60 * 75;
		}
		else if ((sscanf(lptr, "INDEX 01 %02d:%02d:%02d", &mm, &ss, &bb) == 3) ||
				 (sscanf(lptr, "INDEX 1 %02d:%02d:%02d", &mm, &ss, &bb) == 3))
		{
			index1 = bb + ss * 75 + mm * 60 * 75;

			if (!table->tracks[table->last].f.opened())
			{
				// Catch absent INDEX0 (no pregap) to fix calculations afterwards
				if (!index0)
					index0 = index1;

				table->tracks[table->last].start = index1;
				table->tracks[table->last].pregap = index1 - index0;
				// Subtract the fake 150 sector pregap used for the first data track
				table->tracks[table->last].offset = index0 * table->tracks[table->last].sector_size;
				table->tracks[table->last - 1].end =
					table->tracks[table->last].start - 1 - table->tracks[table->last].pregap;
			}
			else
			{
				table->tracks[table->last].start = table->end + index0 + index1;
				table->tracks[table->last].pregap = index1 - index0;
				table->end += (table->tracks[table->last].f.size / table->tracks[table->last].sector_size);
				table->tracks[table->last].offset = 0;
			}
			table->tracks[table->last].end = table->end - 1;
			table->last++;
			if (table->last >= 99)
				break;
		}
	}

	for (int i = 0; i < table->last; i++)
	{
		printf("\x1b[32mCUE: Track = %u, start = %u, end = %u, offset = %d, sector_size=%d, type = %u, pregap = "
			   "%u\n\x1b[0m",
			   i,
			   table->tracks[i].start,
			   table->tracks[i].end,
			   table->tracks[i].offset,
			   table->tracks[i].sector_size,
			   table->tracks[i].type,
			   table->tracks[i].pregap);
	}

	return 1;
}

static int load_cd_image(const char* filename, toc_t* table)
{
	int result = 0;

	const char* ext = strrchr(filename, '.');
	if (!ext)
		return 0;

	if (!strncasecmp(".chd", ext, 4))
	{
		result = load_chd(filename, table);
	}
	else if (!strncasecmp(".cue", ext, 4))
	{
		result = load_cue(filename, table);
	}

	return result;
}

static void lba_to_msf(int lba, uint8_t *m, uint8_t *s, uint8_t *f)
{
	// lba==0 is msf==0:2:0 (track 0 pre-gap)
	lba += 150;
	*m = lba / (60 * 75);
	lba -= *m * (60 * 75);
	*s = lba / 75;
	*f = lba % 75;
}

static void prepare_toc_buffer(toc_t* toc)
{
	struct toc_entry* toc_ptr = toc_buffer.data();
	toc_entry_count = 0;

	auto add_entry = [&](uint8_t control, uint8_t track, uint8_t m, uint8_t s, uint8_t f)
	{
		toc_ptr->control = control;
		toc_ptr->track = track;
		toc_ptr->m = m;
		toc_ptr->s = s;
		toc_ptr->f = f;

		toc_ptr++;

		if (toc_entry_count < toc_buffer.size())
			toc_entry_count++;
	};

	for (int i = 0; i < toc->last; i++)
	{
		int lba = toc->tracks[i].start;
		uint8_t m, s, f;
        lba_to_msf(lba, &m, &s, &f);
		add_entry((toc->tracks[i].type ? 0x41 : 0x01), i + 1, m, s, f);
	}
}

int pcfx_chd_hunksize()
{
	if (toc.chd_f)
		return toc.chd_hunksize;

	return 0;
}

static void toc_data(int lba, struct read_toc& out)
{
	if (lba < 0)
	{
		// TOC is expected by the core at lba -65536
        // Starting track is added to the base LBA
		int starting_track = lba + 65536;

		if (toc_entry_count == 0) // catch division by zero
			return;
        out.length = htons(2 + 8 * toc_entry_count);
        out.first_track_num = toc_buffer[0].track;
        out.last_track_num = toc_buffer[toc_entry_count-1].track;

        struct toc_entry* toc_ptr = toc_buffer.data();
        if (starting_track != 0) {
            // Advance to requested starting track
            while (toc_ptr < toc_buffer.data() + toc_entry_count) {
                if (toc_ptr->track >= starting_track)
                    break;
                toc_ptr++;
            }
        }

        size_t desc_idx = 0;
        while (toc_ptr < toc_buffer.data() + toc_entry_count &&
               desc_idx < (sizeof(read_toc::track_desc) /
                           sizeof(read_toc::track_desc[0]))) {
            out.track_desc[desc_idx].adr_control =
                (toc_ptr->control >> 4) | (toc_ptr->control << 4);
            out.track_desc[desc_idx].track_number = toc_ptr->track;
            out.track_desc[desc_idx].mins = toc_ptr->m;
            out.track_desc[desc_idx].secs = toc_ptr->s;
            out.track_desc[desc_idx].frac = toc_ptr->f;
            toc_ptr++;
            desc_idx++;
        }
	}
}

void pcfx_read_cd(uint8_t* buffer, int lba, int cnt)
{
#if 1
	uint8_t am, as, af;
    lba_to_msf(lba, &am, &as, &af);

	printf("req lba=%d, cnt=%d   %02d:%02d:%02d\n",
		   lba,
		   cnt,
		   am,
		   as,
		   af);
#endif

	while (cnt > 0)
	{
		if (lba < 0 || !toc.last)
		{
			// TOC area
			memset(buffer, 0, PCFX_BUFFER_SIZE);
			struct read_toc& toc_out = *reinterpret_cast<struct read_toc*>(buffer);
			toc_data(lba, toc_out);
			buffer += PCFX_BUFFER_SIZE;
		}
		else
		{
			memset(buffer, 0xAA, PCFX_SECTOR_LEN);

			for (int i = 0; i < toc.last; i++)
			{
				if (lba >= (toc.tracks[i].start - toc.tracks[i].pregap) && lba <= toc.tracks[i].end)
				{
					if (!toc.chd_f)
					{
						int pos = toc.tracks[i].offset +
							((lba - toc.tracks[i].start + toc.tracks[i].pregap)
							 * PCFX_SECTOR_LEN);
						FileSeek(&toc.tracks[0].f, pos, SEEK_SET);
					}

					while (cnt)
					{
						if (toc.chd_f)
						{
							int read_lba = lba;
							if (mister_chd_read_sector(toc.chd_f,
													   (read_lba + toc.tracks[i].offset),
													   0,
													   0,
													   PCFX_SECTOR_LEN,
													   buffer,
													   chd_hunkbuf,
													   &chd_hunknum) == CHDERR_NONE)
							{
								if (!toc.tracks[i].type) // CHD requires byteswap of audio data
								{
									for (int swapidx = 0; swapidx < PCFX_SECTOR_LEN; swapidx += 2)
									{
										uint8_t temp = buffer[swapidx];
										buffer[swapidx] = buffer[swapidx + 1];
										buffer[swapidx + 1] = temp;
									}
								}
							}
							else
							{
								printf("\x1b[32mPCFX: CHD read error: %d\n\x1b[0m", lba);
							}
						}
						else
						{
							if (toc.tracks[i].offset)
								FileReadAdv(&toc.tracks[0].f, buffer, PCFX_SECTOR_LEN);
							else
								FileReadAdv(&toc.tracks[i].f, buffer, PCFX_SECTOR_LEN);

						}

						if ((lba + 1) > toc.tracks[i].end)
							break;

						buffer += PCFX_SECTOR_LEN;

						cnt--;
						lba++;
					}
					break;
				}
			}
		}

		cnt--;
		lba++;
	}
}

static void mount_cd(int size, int /*index*/)
{
	// spi_uio_cmd_cont(UIO_SET_SDINFO);
	// spi32_w(size);
	// spi32_w(0);
	// DisableIO();
	// spi_uio_cmd8(UIO_SET_SDSTAT, (1 << index) | 0x80);
	// user_io_bufferinvalidate(0);
    pcfx_img_size = size;
}

void pcfx_mount_cd(int s_index, const char* filename)
{
	int loaded = 0;

	if (strlen(filename))
	{
		if (load_cd_image(filename, &toc) && toc.last)
		{
            // TODO: Mount the CD save image.

			prepare_toc_buffer(&toc);
			// user_io_set_index(0);
			mount_cd(toc.end * PCFX_SECTOR_LEN, s_index);
			loaded = 1;
		}
	}

	if (!loaded)
	{
		printf("Unmount CD\n");
		unload_cue(&toc);
		unload_chd(&toc);
		mount_cd(0, s_index);
	}
}

void pcfx_poll() {}

int pcfx_get_img_size()
{
    return pcfx_img_size;
}
