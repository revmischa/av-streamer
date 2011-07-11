#ifndef __STREAMERXS_H__
#define __STREAMERXS_H__

/* libav streaming XS wrapper header */

#include <libavformat/avformat.h>
#include <libavcodec/avcodec.h>
#include <stdio.h>
#include <stdlib.h>
#include <stdbool.h>


#pragma mark types
typedef enum CodecID    CodecID;
typedef uint8_t         AV_Streamer_FrameBuffer;
typedef double          AV_Streamer_PTS;
typedef short bool_t;


/* borrowed from libav cmdutils */
typedef struct {
    int64_t num_faulty_pts; /// Number of incorrect PTS values so far
    int64_t num_faulty_dts; /// Number of incorrect DTS values so far
    int64_t last_pts;       /// PTS of the last frame
    int64_t last_dts;       /// DTS of the last frame
} PtsCorrectionContext;
void init_pts_correction(PtsCorrectionContext *ctx);
int64_t guess_correct_pts(PtsCorrectionContext *ctx, int64_t pts, int64_t dts);


#endif
