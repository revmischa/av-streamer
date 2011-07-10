#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"

#include "ppport.h"

#include <libavformat/avformat.h>
#include <libavcodec/avcodec.h>
#include <libavutil/pixfmt.h>
#include <libswscale/swscale.h>
#include <pthread.h>
#include <stdio.h>
#include <stdlib.h>
#include <stdbool.h>

#include "StreamerUtils.h"

#define AVS_DEFAULT_PIXFMT PIX_FMT_YUV420P
static float mux_preload   = 0.5;
static float mux_max_delay = 0.7;

#pragma mark globals
static pthread_mutex_t AVFormatCtxMP;

MODULE = AV::Streamer		PACKAGE = AV::Streamer
PROTOTYPES: ENABLE

#pragma mark boot
BOOT:
{
    av_register_all();
    pthread_mutex_init(&AVFormatCtxMP, NULL);
}

#pragma mark methods

AVFormatContext*
avs_open_uri(uri)
char* uri;
    CODE:
    {
        /* avs_open_uri: wrapper around av_open_input_file */

        int lock_status;

        /* use a mutex protect opening a file. I assume this is
         reqiuired because Video::FFmpeg does it */

        lock_status = pthread_mutex_lock(&AVFormatCtxMP);
        if ( lock_status != 0 ) {
            croak("Unable to lock mutex AVFormatCtxMP for %s: %s", uri, sys_errlist[lock_status]);
        };

        AVFormatContext *formatCtx;

        if ( avformat_open_input(&formatCtx, uri, NULL, NULL) != 0 )
            XSRETURN_UNDEF;

        /* make sure we can read the stream */
        int ret = av_find_stream_info(formatCtx);
        if ( ret < 0 ) {
            fprintf(stderr, "Failed to find codec parameters for input %s\n", uri);
            XSRETURN_UNDEF;
        }

        /* unlock mutex */
        lock_status = pthread_mutex_unlock(&AVFormatCtxMP);
        if ( lock_status != 0 ) {
            fprintf(stderr, "Unable to unlock mutex AVFormatCtxMP for %s: %s", uri, sys_errlist[lock_status]);
        };

        RETVAL = formatCtx;
    }
    OUTPUT: RETVAL

CodecID
avs_get_stream_codec_id(stream)
AVStream *stream;
    CODE:
    {
        RETVAL = stream->codec->codec_id;
    }
    OUTPUT: RETVAL

int
avs_open_decoder(codec_ctx, codec_id)
AVCodecContext *codec_ctx;
CodecID codec_id;
    CODE:
    {
        /* find decoder by id */
        AVCodec *codec = avcodec_find_decoder(codec_id);
        if (! codec) {
            fprintf(stderr, "Failed to find codec id=%d\n", codec_id);
            XSRETURN_UNDEF;
        }

        if (avcodec_open(codec_ctx, codec) < 0) {
            fprintf(stderr, "Failed to open codec %s\n", codec->name);
            XSRETURN_UNDEF;
        }

        RETVAL = 1;
    }
    OUTPUT: RETVAL

void
avs_close_codec(codec_ctx)
AVCodecContext *codec_ctx;
    CODE:
    {
        avcodec_close(codec_ctx);
    }

unsigned int
avs_stream_count(fmt)
AVFormatContext* fmt;
    CODE:
        RETVAL = fmt->nb_streams;
    OUTPUT: RETVAL

unsigned short
avs_is_video_stream_index(fmt, index)
AVFormatContext* fmt;
unsigned int index;
    CODE:
        RETVAL = fmt->streams[index]->codec->codec_type == AVMEDIA_TYPE_VIDEO;
    OUTPUT: RETVAL

unsigned short
avs_is_audio_stream_index(fmt, index)
AVFormatContext* fmt;
unsigned int index;
    CODE:
        RETVAL = fmt->streams[index]->codec->codec_type == AVMEDIA_TYPE_AUDIO;
    OUTPUT: RETVAL

unsigned short
avs_is_video_stream(stream)
AVStream* stream;
    CODE:
        RETVAL = stream->codec->codec_type == AVMEDIA_TYPE_VIDEO;
    OUTPUT: RETVAL

unsigned short
avs_is_audio_stream(stream)
AVStream* stream;
    CODE:
        RETVAL = stream->codec->codec_type == AVMEDIA_TYPE_AUDIO;
    OUTPUT: RETVAL


unsigned int
avs_get_stream_index(stream)
AVStream* stream;
    CODE:
        RETVAL = stream->index;
    OUTPUT: RETVAL

AVStream*
avs_get_stream(ctx, idx)
AVFormatContext* ctx;
int idx;
    CODE:
    {
        /* get a stream from a format context by index.
        returns a pointer to the stream context or NULL */
        
        AVStream *stream = ctx->streams[idx];
        if (! stream) XSRETURN_UNDEF;

        RETVAL = stream;
    }
    OUTPUT: RETVAL

AVFrame*
avs_alloc_avframe()
    CODE:
    {
        /* allocate space for an AVFrame struct */
        RETVAL = avcodec_alloc_frame();
    }
    OUTPUT: RETVAL

void
avs_dealloc_avframe(frame)
AVFrame* frame;
    CODE:
    {
        /* dellocate frame storage */
        av_free(frame);
    }
    
void
avs_dealloc_output_buffer(buf)
AVS_FrameBuffer* buf;
    CODE:
    {
        /* dellocate frame buffer storage */
        free(buf);
    }


AVS_FrameBuffer*
avs_alloc_output_buffer(size)
unsigned int size;
    CODE:
        RETVAL = av_mallocz(size);
    OUTPUT:
        RETVAL

AVS_FrameBuffer*
avs_alloc_frame_buffer(codec_ctx, dst_frame, pixformat)
AVCodecContext* codec_ctx;
AVFrame* dst_frame;
int pixformat;
    CODE:
    {
        unsigned int size;
        AVS_FrameBuffer *buf;
                
        /* calculate size of storage required for a frame */
        size = avpicture_get_size(pixformat, codec_ctx->width,
            codec_ctx->height);
        
        /* allocate frame buffer storage */
        buf = malloc(size);
        
        /* assign appropriate parts of buffer to image planes in dst_frame */
        avpicture_fill((AVPicture *)dst_frame, buf, pixformat,
            codec_ctx->width, codec_ctx->height);
        
        RETVAL = buf;
    }
    OUTPUT: RETVAL

AVCodecContext*
avs_get_codec_ctx(stream)
AVStream* stream;
    CODE:
        RETVAL = stream->codec;
    OUTPUT: RETVAL

AVPacket*
avs_alloc_avpacket()
    CODE:
        RETVAL = av_mallocz(sizeof(struct AVPacket));
    OUTPUT: RETVAL

void
avs_init_avpacket(pkt)
AVPacket *pkt;
    CODE:
        av_init_packet(pkt);

int
avs_get_avpacket_stream_index(pkt)
AVPacket *pkt;
    CODE:
        RETVAL = pkt->stream_index;
    OUTPUT: RETVAL

AVS_PTS
avs_no_pts_value()
    CODE: { RETVAL = AV_NOPTS_VALUE; }
    OUTPUT: RETVAL

AVS_PTS
avs_get_avpacket_dts(pkt)
AVPacket *pkt;
    CODE:
        RETVAL = pkt->dts;
    OUTPUT: RETVAL

AVS_PTS
avs_get_avframe_dts(frame)
AVFrame *frame;
    CODE:
        RETVAL = frame->pkt_dts;
    OUTPUT: RETVAL

AVS_PTS
avs_get_avframe_pts(frame)
AVFrame *frame;
    CODE:
        RETVAL = frame->pkt_pts;
    OUTPUT: RETVAL

AVS_PTS
avs_guess_correct_pts(ctx, in_pts, dts)
PtsCorrectionContext *ctx;
AVS_PTS in_pts;
AVS_PTS dts;
    CODE: { RETVAL = guess_correct_pts(ctx, in_pts, dts); }
    OUTPUT: RETVAL
    
AVS_PTS
avs_get_avpacket_scaled_pts(pkt, stream, global_pts)
AVPacket *pkt;
AVStream *stream;
AVS_PTS global_pts;
    CODE:
    {
        double pts;

        /* if we got a DTS, use it. if not, use global PTS if exists, otherwise 0 */
        if (pkt->dts == AV_NOPTS_VALUE && global_pts != AV_NOPTS_VALUE)
            pts = global_pts;
        else if (pkt->dts != AV_NOPTS_VALUE)
            pts = pkt->dts;
        else
            pts = 0;

        pts *= av_q2d(stream->time_base);

        RETVAL = pts;
    }
    OUTPUT: RETVAL

void
avs_dealloc_avpacket(pkt)
AVPacket* pkt;
    CODE:
    {
      av_free(pkt);
    }

void
avs_free_avpacket_data(pkt)
AVPacket* pkt;
    CODE:
       av_free_packet(pkt);

int
avs_read_packet(ctx, pkt)
AVFormatContext *ctx;
AVPacket *pkt;
    CODE:
    {
        /* read one frame packet, wants allocated pkt for storage. call
            avs_free_avpacket when done with the pkt */

        RETVAL = av_read_frame(ctx, pkt);
    }
    OUTPUT: RETVAL

int
avs_write_frame(ctx, pkt)
AVFormatContext *ctx;
AVPacket *pkt;
    CODE:
    {
        /* write frame to output. you may need to encode the frame first */
        RETVAL = av_interleaved_write_frame(ctx, pkt);
    }
    OUTPUT: RETVAL

void
avs_raw_stream_packet(ipkt, opkt, ist, ost)
AVPacket *ipkt;
AVPacket *opkt;
AVStream *ist;
AVStream *ost;
    CODE:
    {
        /* basically copies input packet into output packet, rescaling time */

        /* can use as starting oavset later i think */
        int start_time = 0;
        int64_t ost_tb_start_time = av_rescale_q(start_time, AV_TIME_BASE_Q, ost->time_base);

        opkt->stream_index = ost->index;
        if (ipkt->pts != AV_NOPTS_VALUE)
            opkt->pts = av_rescale_q(ipkt->pts, ist->time_base, ost->time_base) - ost_tb_start_time;
        else
            opkt->pts = AV_NOPTS_VALUE;
 
  /* TODO: where does ist->pts come from ? */
   /*        if (ipkt->dts == AV_NOPTS_VALUE)
            opkt->dts = av_rescale_q(ist->pts, AV_TIME_BASE_Q, ost->time_base);
        else 
  */
            opkt->dts = av_rescale_q(ipkt->dts, ist->time_base, ost->time_base);
            
        opkt->dts -= ost_tb_start_time;
        opkt->duration = av_rescale_q(ipkt->duration, ist->time_base, ost->time_base);
        opkt->flags = ipkt->flags;

        opkt->data = ipkt->data;
        opkt->size = ipkt->size;

        ost->codec->frame_number++;
    }

int
avs_encode_video_frame(format_ctx, ostream, iframe, opkt, obuf, obuf_size, pts)
AVFormatContext* format_ctx;
AVStream* ostream;
AVFrame* iframe;
AVPacket* opkt;
AVS_FrameBuffer* obuf;
unsigned int obuf_size;
AVS_PTS pts;
    CODE:
    {
        /* TODO: image resampling with sws_scale() */
        int status;
        AVCodecContext *enc = ostream->codec;

        /* encode frame into opkt */
        opkt->stream_index = ostream->index;
        status = avcodec_encode_video(enc, obuf, obuf_size, iframe);

        RETVAL = status;

        if (status > 0) {
            opkt->size = status;
            opkt->data = obuf;
            
            if (enc->coded_frame && enc->coded_frame->pts != AV_NOPTS_VALUE)
                opkt->pts = av_rescale_q(enc->coded_frame->pts, enc->time_base, ostream->time_base);

            if (enc->coded_frame && enc->coded_frame->key_frame)
                opkt->flags |= AV_PKT_FLAG_KEY;
       }
    }
    OUTPUT: RETVAL

int
avs_decode_video_frame(format_ctx, istream, ipkt, pts_ctx, OUT AVS_PTS pts, oframe)
AVFormatContext* format_ctx;
AVStream* istream;
AVPacket* ipkt;
PtsCorrectionContext *pts_ctx;
AVFrame* oframe;
     CODE:
     {
         int status, frame_was_decoded;
         
         /* reset frame to default values */
         avcodec_get_frame_defaults(oframe);

         status = avcodec_decode_video2(istream->codec,
             oframe, &frame_was_decoded, ipkt);

         /* status = frame size if frame was decoded and no error */
         RETVAL = status;

         if (status < 0) {
             /* error */
             return;
         }

         if (! frame_was_decoded) {
             /* not enough data to decode a frame */
             XSRETURN_UNDEF;
         }

         /* figure out decoded frame PTS */
         if (ipkt->pts == AV_NOPTS_VALUE)
             pts = 0;
         else
             pts = guess_correct_pts(pts_ctx, oframe->pkt_pts, oframe->pkt_dts);

             
     }
     OUTPUT: RETVAL

AVCodec*
avs_get_codec_ctx_codec(c)
AVCodecContext* c;
    CODE:
        RETVAL = c->codec;
    OUTPUT: RETVAL

const char*
avs_get_codec_ctx_codec_name(c)
AVCodecContext* c;
    CODE:
        RETVAL = c->codec->name;
    OUTPUT: RETVAL

unsigned int
avs_get_codec_ctx_width(c)
AVCodecContext* c;
    CODE:
        RETVAL = c->width;
    OUTPUT: RETVAL

unsigned int
avs_get_codec_ctx_height(c)
AVCodecContext* c;
    CODE:
        RETVAL = c->height;
    OUTPUT: RETVAL

unsigned int
avs_get_codec_ctx_bitrate(c)
AVCodecContext* c;
    CODE:
        RETVAL = c->bit_rate;
    OUTPUT: RETVAL
    
int
avs_get_codec_ctx_base_den(c)
AVCodecContext* c;
    CODE:
        RETVAL = c->time_base.den;
    OUTPUT: RETVAL

int
avs_get_codec_ctx_base_num(c)
AVCodecContext* c;
    CODE:
        RETVAL = c->time_base.num;
    OUTPUT: RETVAL

int
avs_get_codec_ctx_pixfmt(c)
AVCodecContext* c;
    CODE:
        RETVAL = c->pix_fmt;
    OUTPUT: RETVAL

unsigned int
avs_get_codec_ctx_gopsize(c)
AVCodecContext* c;
    CODE:
        RETVAL = c->gop_size;
    OUTPUT: RETVAL

unsigned int
avs_get_codec_ctx_channels(c)
AVCodecContext* c;
    CODE:
        RETVAL = c->channels;
    OUTPUT: RETVAL

unsigned int
avs_get_codec_ctx_sample_rate(c)
AVCodecContext* c;
    CODE:
        RETVAL = c->sample_rate;
    OUTPUT: RETVAL

unsigned int
avs_get_codec_ctx_frame_delay(c)
AVCodecContext* c;
    CODE:
        RETVAL = av_q2d(c->time_base);
    OUTPUT: RETVAL

int
avs_get_frame_repeat_pict(f)
AVFrame* f;
    CODE:
        RETVAL = f->repeat_pict;
    OUTPUT: RETVAL

char*
avs_get_frame_line_pointer(frame, y)
AVFrame* frame;
unsigned int y;
    CODE:
    {
        RETVAL = frame->data[0] + y * frame->linesize[0];
    }
    OUTPUT: RETVAL

unsigned int
avs_get_frame_size(frame, line_size, height)
AVFrame* frame;
unsigned int line_size;
unsigned int height;
    CODE:
    {
        unsigned int frame_size = line_size * height;

        RETVAL = frame_size;
    }
    OUTPUT: RETVAL
    
unsigned int
avs_get_line_size(frame, width)
AVFrame* frame;
unsigned int width;
    CODE:
    {
        unsigned int line_size = frame->linesize[0] + frame->linesize[1] 
            + frame->linesize[2] + frame->linesize[3] * width;

        RETVAL = line_size;
    }
    OUTPUT: RETVAL

SV*
avs_get_frame_data(frame, width, height, line_size, frame_size)
AVFrame* frame;
unsigned int width;
unsigned int height;
unsigned int line_size;
unsigned int frame_size;
    CODE:
    {
        char *buf, *oavset;
        unsigned int y;

        buf = av_mallocz(frame_size);
        
        oavset = buf;
        for ( y = 0; y < height; y++ ) {
            memcpy(oavset, frame->data[0] + y * frame->linesize[0], line_size);
            oavset += line_size;
        }

        SV *ret = newSVpv(buf, frame_size);
        free(buf);
        
        RETVAL = ret;
    }
    OUTPUT: RETVAL

AVOutputFormat*
avs_find_output_format(uri, format)
char* uri;
char* format;
    CODE:
    {
        AVOutputFormat *fmt;

        /* attempt to guess the format from the filename (and format if supplied) */
        fmt = av_guess_format(format, uri, NULL);
        if (! fmt) {
            XSRETURN_UNDEF;
        }

        RETVAL = fmt;
    }
    OUTPUT: RETVAL

AVFormatContext*
avs_create_output_format_ctx(ofmt, uri)
AVOutputFormat* ofmt;
char* uri;
    CODE:
    {
        AVFormatContext *ctx;

        ctx = avformat_alloc_context();
        if (! ctx) {
            /* out of memory! */
            fprintf(stderr, "Unable to alloc format context, out of memory!\n");
            XSRETURN_UNDEF;
        }

        ctx->oformat = ofmt;
        snprintf(ctx->filename, sizeof(ctx->filename), "%s", uri);

        ctx->pb = NULL;
        /* open output file for writing (if applicable) */
        if (! (ofmt->flags & AVFMT_NOFILE)) {
            if (avio_open(&ctx->pb, uri, AVIO_FLAG_WRITE) < 0) {
                fprintf(stderr, "Could not open '%s' for writing\n", uri);
                XSRETURN_UNDEF;
            }
        }

        /* TODO: copy metadata from input? */

        ctx->preload   = (int)(mux_preload*AV_TIME_BASE);
        ctx->max_delay = (int)(mux_max_delay*AV_TIME_BASE);

        RETVAL = ctx;
     }
     OUTPUT: RETVAL

void
avs_close_output_format_ctx(ctx)
AVFormatContext* ctx;
    CODE:
    {
        /* close file if open */
        if (! (ctx->oformat->flags & AVFMT_NOFILE)) {
            avio_close(ctx->pb);
        }
    }

void
avs_dealloc_stream(stream)
AVStream* stream;
    CODE:
    {
//        if (stream->codec)
//            av_freep(&stream->codec);

        av_freep(&stream);
    }

void
avs_set_ctx_metadata(ctx, key, value)
AVFormatContext* ctx;
const char* key;
const char* value;
    CODE:
    {
        av_dict_set(&ctx->metadata, key, value, 0);
    }

    
void
avs_write_header_and_metadata(ctx)
AVFormatContext* ctx;
    CODE:
    {
        avformat_write_header(ctx, &ctx->metadata);
        av_dict_free(&ctx->metadata);
    }

void
avs_write_trailer(ctx)
AVFormatContext* ctx;
    CODE:
    {
        av_write_trailer(ctx);
    }    

AVStream*
avs_create_stream(ofmt)
AVFormatContext *ofmt;
    CODE:
    {
        AVStream *vs = NULL;

        vs = av_new_stream(ofmt, 0);
        if (! vs) {
            fprintf(stderr, "av_new_stream failed\n");
            XSRETURN_UNDEF;
        }

        RETVAL = vs;
    }
    OUTPUT: RETVAL

int
avs_copy_stream_params(ofmt, istream, ostream)
AVStream *istream;
AVStream *ostream;
AVFormatContext *ofmt;
    CODE:
    {
        AVCodecContext *ocodec, *icodec;

        icodec = istream->codec;
        ocodec = ostream->codec;

        ostream->disposition = istream->disposition;
        ocodec->bits_per_raw_sample = icodec->bits_per_raw_sample;
        ocodec->chroma_sample_location = icodec->chroma_sample_location;

        uint64_t extra_size = (uint64_t)icodec->extradata_size + FF_INPUT_BUFFER_PADDING_SIZE;
        if (extra_size > INT_MAX)
            XSRETURN_UNDEF;

        ocodec->codec_id = icodec->codec_id;
        ocodec->codec_type = icodec->codec_type;

        if (! ocodec->codec_tag) {
          if (! ofmt->oformat->codec_tag
              || av_codec_get_id (ofmt->oformat->codec_tag, icodec->codec_tag) == ocodec->codec_id
              || av_codec_get_tag(ofmt->oformat->codec_tag, icodec->codec_id) <= 0)
            ocodec->codec_tag = icodec->codec_tag;
        }
 
        ocodec->bit_rate       = icodec->bit_rate;
        ocodec->rc_max_rate    = icodec->rc_max_rate;
        ocodec->rc_buffer_size = icodec->rc_buffer_size;
        ocodec->extradata      = av_mallocz(extra_size);
        if (! ocodec->extradata)
            XSRETURN_UNDEF;

        memcpy(ocodec->extradata, icodec->extradata, icodec->extradata_size);
        ocodec->extradata_size = icodec->extradata_size;
        if (av_q2d(icodec->time_base)*icodec->ticks_per_frame > av_q2d(istream->time_base) && av_q2d(istream->time_base) < 1.0/1000){
          ocodec->time_base = icodec->time_base;
          ocodec->time_base.num *= icodec->ticks_per_frame;
          av_reduce(&ocodec->time_base.num, &ocodec->time_base.den,
                    ocodec->time_base.num, ocodec->time_base.den, INT_MAX);
        } else {
          ocodec->time_base = istream->time_base;
        }

        switch (ocodec->codec_type) {
            case AVMEDIA_TYPE_AUDIO:
              ocodec->channel_layout = icodec->channel_layout;
              ocodec->sample_rate = icodec->sample_rate;
              ocodec->channels = icodec->channels;
              ocodec->frame_size = icodec->frame_size;
              ocodec->block_align = icodec->block_align;
              if (ocodec->block_align == 1 && ocodec->codec_id == CODEC_ID_MP3)
                  ocodec->block_align= 0;
                  if (ocodec->codec_id == CODEC_ID_AC3)
                    ocodec->block_align= 0;
                  break;
             case AVMEDIA_TYPE_VIDEO:
                 ocodec->pix_fmt = icodec->pix_fmt;
                 ocodec->width = icodec->width;
                 ocodec->height = icodec->height;
                 ocodec->has_b_frames = icodec->has_b_frames;
                 break;
             case AVMEDIA_TYPE_SUBTITLE:
                 ocodec->width = icodec->width;
                 ocodec->height = icodec->height;
                 break;
        }

        RETVAL = 1;
    }
    OUTPUT: RETVAL

int
avs_set_video_stream_params(ofmt, vs, codec_name, stream_copy, width, height, bitrate, base_num, base_den, gopsize, pixfmt)
AVFormatContext* ofmt;
AVStream *vs;
const char *codec_name;
unsigned short stream_copy;
unsigned int width;
unsigned int height;
unsigned int bitrate;
int base_num;
int base_den;
unsigned int gopsize;
int pixfmt;
    CODE:
    {
        int i;

        if (! pixfmt)
            pixfmt = AVS_DEFAULT_PIXFMT;
                
        if (! codec_name && ofmt->oformat->video_codec == CODEC_ID_NONE) {
            fprintf(stderr, "No encoder specified for avs_set_video_stream_params\n");
            XSRETURN_UNDEF;
        }

        vs->stream_copy = stream_copy;

        AVCodecContext *c = vs->codec;
        AVCodec *codec = NULL;

        if (codec_name) {
            /* look up codec */
            codec = avcodec_find_encoder_by_name(codec_name);
            if (! codec) {
                fprintf(stderr, "failed to find encoder for codec named '%s'\n", codec_name);
                XSRETURN_UNDEF;
            }
        } else {
            /* use default codec for output format */
            codec = avcodec_find_encoder(ofmt->oformat->video_codec);
            if (! codec) {
                fprintf(stderr, "failed to find default encoder for codec id %d\n", c->codec_id);
                XSRETURN_UNDEF;
            }
            printf("using default codec\n");
        }

        c->codec_type = AVMEDIA_TYPE_VIDEO;

        /* put sample parameters */
        c->bit_rate = bitrate;
        
        /* resolution must be a multiple of two */
        c->width = width;
        c->height = height;
        
        i = av_gcd(base_num, base_den);
        c->time_base = (AVRational){ base_num / i, base_den / i };
        
        c->gop_size = gopsize; /* emit one intra frame every gopsize frames at most */
        c->pix_fmt = pixfmt;

        printf("\nwidth: %d, height: %d, bitrate: %u, framerate: %i/%i, timebase: %i/%i, pixfmt: %d, gopsize: %d\n",
            width, height, bitrate, vs->r_frame_rate.num, vs->r_frame_rate.den, base_num, base_den, pixfmt, gopsize);

        if (c->codec_id == CODEC_ID_MPEG1VIDEO) {
            c->mb_decision = 2;
        }

        /* some formats want stream headers to be separate */
        if (ofmt->oformat->flags & AVFMT_GLOBALHEADER)
            c->flags |= CODEC_FLAG_GLOBAL_HEADER;

        /* open video stream codec */
        if (avcodec_open(c, codec) < 0) {
            fprintf(stderr, "failed to open codec\n");
            XSRETURN_UNDEF;
        }

        av_dump_format(ofmt, 0, "output", 1);

        RETVAL = 1;
    }
    OUTPUT: RETVAL        

int
avs_set_audio_stream_params(ofmt, as, codec_name, stream_copy, channels, sample_rate, bit_rate)
AVFormatContext* ofmt;
AVStream *as;
const char *codec_name;
unsigned short stream_copy;
unsigned int channels;
unsigned int sample_rate;
unsigned int bit_rate;
    CODE:
    {
        if (! codec_name && ofmt->oformat->audio_codec == CODEC_ID_NONE) {
            fprintf(stderr, "No encoder specified for avs_set_audio_stream_params\n");
            XSRETURN_UNDEF;
        }

        as->stream_copy = stream_copy;

        AVCodecContext *c = as->codec;
        AVCodec *codec = NULL;

        if (codec_name) {
            /* look up codec */
            codec = avcodec_find_encoder_by_name(codec_name);
            if (! codec) {
                fprintf(stderr, "failed to find encoder for codec named '%s'\n", codec_name);
                XSRETURN_UNDEF;
            }
        } else {
            /* use default codec for output format */
            codec = avcodec_find_encoder(ofmt->oformat->audio_codec);
            if (! codec) {
                fprintf(stderr, "failed to find default encoder for audio codec id %d\n", c->codec_id);
                XSRETURN_UNDEF;
            }
            printf("using default codec\n");
        }

        c->codec_type = AVMEDIA_TYPE_AUDIO;

        /* put sample parameters */
        c->bit_rate = bit_rate;
        c->sample_rate = sample_rate;
        c->channels = channels;

        RETVAL = 1;
    }
    OUTPUT: RETVAL

AVStream*
avs_new_output_audio_stream(ctx, sample_rate, bit_rate)
AVFormatContext* ctx;
unsigned int sample_rate;
unsigned int bit_rate;
    CODE:
    {
        AVStream *as = NULL;
        int i;

                
        if (ctx->oformat->audio_codec == CODEC_ID_NONE)
            XSRETURN_UNDEF;
        
        AVCodecContext *c;
        as = av_new_stream(ctx, 0);
        if (! as) {
            XSRETURN_UNDEF;
        }
        
        as->stream_copy = 1;
        
        c = as->codec;
        c->codec_id = ctx->oformat->audio_codec;
        c->codec_type = AVMEDIA_TYPE_VIDEO;

        /* put sample parameters */
        c->bit_rate = bit_rate;
        c->sample_rate = sample_rate;
        c->channels = 2;
        c->sample_fmt = AV_SAMPLE_FMT_S16;
            
        /* open audio stream codec */
        AVCodec *codec;
        codec = avcodec_find_encoder(c->codec_id);
        if (! codec) {
            fprintf(stderr, "failed to find encoder");
            return;
        }

        av_dump_format(ctx, 0, "output", 1);
            
        if (avcodec_open(c, codec) < 0) {
            fprintf(stderr, "failed to open codec");
            return;
        }

        RETVAL = as;
    }
    OUTPUT: RETVAL

void
avs_close_stream(ctx, stream)
AVFormatContext* ctx;
AVStream* stream;
    CODE:
    {
        avcodec_close(stream->codec);
    }

void
avs_dump_format(ctx, title)
AVFormatContext* ctx;
char* title;
    CODE:
    {
        /* dumps information about the context to stderr */
        av_dump_format(ctx, 0, title, false);
    }

void
avs_close_input_file(ctx)
AVFormatContext* ctx;
    CODE:
    {
        av_close_input_file(ctx);
    }

void
avs_destroy_context(ctx)
AVFormatContext* ctx;
    CODE:
    {
        av_free(ctx);
    }




 # borrowed from libav cmdutils

void
avs_destroy_pts_correction_context(ctx)
AVFormatContext* ctx;
    CODE:
    {
        av_free(ctx);
    }

PtsCorrectionContext*
avs_alloc_and_init_pts_correction_context()
    CODE:
        PtsCorrectionContext *pcc = av_mallocz(sizeof(PtsCorrectionContext));
        init_pts_correction(pcc);
        RETVAL = pcc;
    OUTPUT: RETVAL
