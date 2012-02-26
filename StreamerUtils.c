#include "Streamer.h"

AVCodec* _avs_find_encoder(AVFormatContext *ctx, const char *codec_name, int media_type) {
  AVCodec *codec = NULL;

  if (codec_name) {
    /* look up codec by name */
    codec = avcodec_find_encoder_by_name(codec_name);
    if (! codec)
      fprintf(stderr, "failed to find encoder for codec %s\n", codec_name);
  }

  if (! codec) {
    /* use default codec for output format */
    switch (media_type) {
    case AVMEDIA_TYPE_VIDEO:
      codec = avcodec_find_encoder(ctx->oformat->video_codec);
      break;
    case AVMEDIA_TYPE_AUDIO:
      codec = avcodec_find_encoder(ctx->oformat->audio_codec);
      break;
    default:
      fprintf(stderr, "unable to find default codec for unknown media type\n");
      break;
    }
    
    printf("using default codec\n");
  }

  if (! codec) {
    fprintf(stderr, "failed to find default encoder\n");
  }

  return codec;
}

AVStream* _avs_create_output_stream(AVFormatContext *ctx, AVCodec *codec) {   
  /* create new stream */
  /* this creates a new codec context for us in as->codec, with defaults from codec */
  AVStream *as = avformat_new_stream(ctx, codec);
  if (! as) {
    return NULL;
  }

  return as;
}

void init_pts_correction(PtsCorrectionContext *ctx)
{
    ctx->num_faulty_pts = ctx->num_faulty_dts = 0;
    ctx->last_pts = ctx->last_dts = INT64_MIN;
}

int64_t guess_correct_pts(PtsCorrectionContext *ctx, int64_t reordered_pts, int64_t dts)
{
    int64_t pts = AV_NOPTS_VALUE;

    if (dts != AV_NOPTS_VALUE) {
        ctx->num_faulty_dts += dts <= ctx->last_dts;
        ctx->last_dts = dts;
    }
    if (reordered_pts != AV_NOPTS_VALUE) {
        ctx->num_faulty_pts += reordered_pts <= ctx->last_pts;
        ctx->last_pts = reordered_pts;
    }
    if ((ctx->num_faulty_pts<=ctx->num_faulty_dts || dts == AV_NOPTS_VALUE)
       && reordered_pts != AV_NOPTS_VALUE)
        pts = reordered_pts;
    else
        pts = dts;

    return pts;
}
