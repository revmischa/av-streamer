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

#include "Streamer.h"

#define AVS_DEFAULT_PIXFMT PIX_FMT_YUV420P
static float mux_max_delay = 0.7;

#pragma mark globals
static pthread_mutex_t AVFormatCtxMP;

MODULE = AV::Streamer		PACKAGE = AV::Streamer
PROTOTYPES: ENABLE

#pragma mark boot
BOOT:
{
    av_register_all();
    avformat_network_init();
    pthread_mutex_init(&AVFormatCtxMP, NULL);
}

#pragma mark methods

# avs_open_uri: wrapper around av_open_input_file
AVFormatContext*
avs_open_uri(char *uri)
    CODE:
    {
        int lock_status;

        /* use a mutex protect opening a file. I assume this is
         reqiuired because Video::FFmpeg does it */

        lock_status = pthread_mutex_lock(&AVFormatCtxMP);
        if ( lock_status != 0 ) {
            croak("Unable to lock mutex AVFormatCtxMP for %s: %s", uri, sys_errlist[lock_status]);
        };

        AVFormatContext *format_ctx = NULL;
        
        /* note: format_ctx allocated for us on success */
        if ( avformat_open_input(&format_ctx, uri, NULL, NULL) != 0 )
            XSRETURN_UNDEF;

        /* make sure we can read the stream */
        int ret = avformat_find_stream_info(format_ctx, NULL);
        if ( ret < 0 ) {
            fprintf(stderr, "Failed to find codec parameters for input %s\n", uri);
            XSRETURN_UNDEF;
        }

        /* unlock mutex */
        lock_status = pthread_mutex_unlock(&AVFormatCtxMP);
        if ( lock_status != 0 ) {
            fprintf(stderr, "Unable to unlock mutex AVFormatCtxMP for %s: %s", uri, sys_errlist[lock_status]);
        };

        RETVAL = format_ctx;
    }
    OUTPUT: RETVAL

CodecID
avs_get_stream_codec_id(AVStream *stream)
    CODE:
        RETVAL = stream->codec->codec_id;
    OUTPUT: RETVAL

int
avs_get_stream_base_den(AVStream *s)
    CODE:
        RETVAL = s->time_base.den;
    OUTPUT: RETVAL

int
avs_get_stream_base_num(AVStream *s)
    CODE:
        RETVAL = s->time_base.num;
    OUTPUT: RETVAL

# find decoder by id
int
avs_open_decoder(AVCodecContext *codec_ctx, CodecID codec_id)
    CODE:
    {
        AVCodec *codec = avcodec_find_decoder(codec_id);
        if (! codec) {
            fprintf(stderr, "Failed to find codec id=%d\n", codec_id);
            XSRETURN_UNDEF;
        }

        if (avcodec_open2(codec_ctx, codec, NULL) < 0) {
            fprintf(stderr, "Failed to open codec %s\n", codec->name);
            XSRETURN_UNDEF;
        }

        RETVAL = 1;
    }
    OUTPUT: RETVAL

void
avs_close_codec(AVCodecContext *codec_ctx)
    CODE:
        avcodec_close(codec_ctx);

unsigned int
avs_stream_count(AVFormatContext *fmt)
    CODE:
        RETVAL = fmt->nb_streams;
    OUTPUT: RETVAL

unsigned short
avs_is_video_stream_index(AVFormatContext *fmt, unsigned int index)
    CODE:
        RETVAL = fmt->streams[index]->codec->codec_type == AVMEDIA_TYPE_VIDEO;
    OUTPUT: RETVAL

unsigned short
avs_is_audio_stream_index(AVFormatContext *fmt, unsigned int index)
    CODE:
        RETVAL = fmt->streams[index]->codec->codec_type == AVMEDIA_TYPE_AUDIO;
    OUTPUT: RETVAL

unsigned short
avs_is_video_stream(AVStream *stream)
    CODE:
        RETVAL = stream->codec->codec_type == AVMEDIA_TYPE_VIDEO;
    OUTPUT: RETVAL

unsigned short
avs_is_audio_stream(AVStream *stream)
    CODE:
        RETVAL = stream->codec->codec_type == AVMEDIA_TYPE_AUDIO;
    OUTPUT: RETVAL

unsigned int
avs_get_stream_index(AVStream *stream)
    CODE:
        RETVAL = stream->index;
    OUTPUT: RETVAL

# get a stream from a format context by index.
# returns a pointer to the stream context or NULL
AVStream*
avs_get_stream(AVFormatContext *ctx, unsigned int idx)
    CODE:
    {
        
        AVStream *stream = ctx->streams[idx];
        if (! stream) XSRETURN_UNDEF;

        RETVAL = stream;
    }
    OUTPUT: RETVAL

# allocate space for an AVFrame struct
AVFrame*
avs_alloc_avframe()
    CODE:
        RETVAL = avcodec_alloc_frame();
    OUTPUT: RETVAL

# deallocate frame storage
void
avs_dealloc_avframe(AVFrame *frame)
    CODE:
        av_free(frame);
    
# dellocate frame buffer storage
void
avs_dealloc_output_buffer(AVSFrameBuffer *buf)
    CODE:
        free(buf);

AVSFrameBuffer*
avs_alloc_frame_buffer(AVCodecContext *codec_ctx, AVFrame *dst_frame, int pixformat)
    CODE:
    {
        unsigned int size;
        AVSFrameBuffer *buf;
                
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
avs_get_codec_ctx(AVStream *stream)
    CODE:
        RETVAL = stream->codec;
    OUTPUT: RETVAL

AVPacket*
avs_alloc_avpacket()
    CODE:
        RETVAL = av_mallocz(sizeof(struct AVPacket));
    OUTPUT: RETVAL

int
avs_get_avpacket_stream_index(AVPacket *pkt)
    CODE:
        RETVAL = pkt->stream_index;
    OUTPUT: RETVAL

AVSPTS
avs_no_pts_value()
    CODE:
        RETVAL = AV_NOPTS_VALUE;
    OUTPUT: RETVAL

AVSPTS
avs_get_avpacket_dts(AVPacket *pkt)
    CODE:
        RETVAL = pkt->dts;
    OUTPUT: RETVAL

AVSPTS
avs_get_avpacket_pts(AVPacket *pkt)
    CODE:
        RETVAL = pkt->pts;
    OUTPUT: RETVAL

AVSPTS
avs_get_avframe_pkt_dts(AVFrame *frame)
    CODE:
        RETVAL = frame->pkt_dts;
    OUTPUT: RETVAL

AVSPTS
avs_get_avframe_pts(AVFrame *frame)
    CODE:
        RETVAL = frame->pts;
    OUTPUT: RETVAL

AVSPTS
avs_guess_correct_pts(PtsCorrectionContext *ctx, AVSPTS in_pts, AVSPTS dts)
    CODE:
        RETVAL = guess_correct_pts(ctx, in_pts, dts);
    OUTPUT: RETVAL

AVSPTS
avs_scale_pts(AVSPTS pts, AVStream *stream)
     CODE:
     {
         pts *= av_q2d(stream->time_base);
         RETVAL = pts;
     }
     OUTPUT: RETVAL

void
avs_dealloc_avpacket(AVPacket *pkt)
    CODE:
        av_free(pkt);

void
avs_free_avpacket_data(AVPacket *pkt)
    CODE:
        av_free_packet(pkt);

# read one frame packet, wants allocated pkt for storage. call
# avs_free_avpacket when done with the pkt
int
avs_read_frame(AVFormatContext *ctx, AVPacket *pkt)
    CODE:
        RETVAL = av_read_frame(ctx, pkt);
    OUTPUT: RETVAL

# write frame to output. you may need to encode the frame first
int
avs_write_frame(AVFormatContext *ctx, AVPacket *pkt)
    CODE:
        RETVAL = av_interleaved_write_frame(ctx, pkt);
    OUTPUT: RETVAL

# basically copies input packet into output packet, rescaling time
void
avs_raw_stream_packet(AVPacket *ipkt, AVPacket *opkt, AVStream *ist, AVStream *ost)
    CODE:
    {
        /* can use as starting oavset later i think */
        int start_time = 0;
        int64_t ost_tb_start_time = av_rescale_q(start_time, AV_TIME_BASE_Q, ost->time_base);

        opkt->stream_index = ost->index;
        if (ipkt->pts != AV_NOPTS_VALUE) {
            opkt->pts = av_rescale_q(ipkt->pts, ist->time_base, ost->time_base) - ost_tb_start_time;
        } else {
            opkt->pts = AV_NOPTS_VALUE;
        }

        opkt->dts -= ost_tb_start_time;
        opkt->duration = av_rescale_q(ipkt->duration, ist->time_base, ost->time_base);
        opkt->flags = ipkt->flags;

        opkt->data = ipkt->data;
        opkt->size = ipkt->size;

        ost->codec->frame_number++;
    }

# encode iframe into opkt
int
avs_encode_video_frame(AVFormatContext *format_ctx, AVStream *ostream, AVFrame *iframe, AVPacket *opkt, AVSFrameBuffer *obuf, unsigned int obuf_size, AVSPTS pts)
    CODE:
    {
        /* TODO: image resampling with sws_scale() */
        int status, got_packet;
        AVCodecContext *enc = ostream->codec;

        av_init_packet(opkt);

        /* we are passing our own buffer to use to encode_video2 */
        /* (via opkt) */
        opkt->data = obuf;
        opkt->size = obuf_size;
        
        /* encode frame into opkt */
        status = avcodec_encode_video2(enc, opkt, iframe, &got_packet);
        opkt->stream_index = ostream->index;
        
        RETVAL = status;

        if (status != 0) {
            /* failure */
            fprintf(stderr, "Failed to encode video, code %d\n", status);
            return;
        }

        printf("coded packet, size: %d, packet pts: %l, enc pts: %l\n",
            opkt->size, opkt->pts, enc->coded_frame->pts);
            
        if (enc->coded_frame && enc->coded_frame->pts != AV_NOPTS_VALUE) {
                opkt->pts = av_rescale_q(enc->coded_frame->pts, enc->time_base, ostream->time_base);

            if (enc->coded_frame && enc->coded_frame->key_frame)
                opkt->flags |= AV_PKT_FLAG_KEY;
       }

       /* need to set stream PTS as well */
       /* ostream->pts = enc->coded_frame->pts; */
    }
    OUTPUT: RETVAL

# decode ipkt into oframe
int
avs_decode_video_frame(AVFormatContext *format_ctx, AVStream *istream, AVPacket *ipkt, PtsCorrectionContext *pts_ctx, AVFrame *oframe)
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

         /* figure out PTS to stash in decoded frame */
         if (oframe->pts == AV_NOPTS_VALUE) {
             if (istream->pts.val)
                 oframe->pts = (double)istream->pts.val * istream->time_base.num / istream->time_base.den;
             else
                 oframe->pts = 0;
         } else {
             oframe->pts = guess_correct_pts(pts_ctx, oframe->pkt_pts, oframe->pkt_dts);
         }
     }
     OUTPUT: RETVAL

AVCodec*
avs_get_codec_ctx_codec(AVCodecContext *c)
    CODE:
        RETVAL = c->codec;
    OUTPUT: RETVAL

const char*
avs_get_codec_ctx_codec_name(AVCodecContext *c)
    CODE:
        RETVAL = c->codec->name;
    OUTPUT: RETVAL

unsigned int
avs_get_codec_ctx_width(AVCodecContext *c)
    CODE:
        RETVAL = c->width;
    OUTPUT: RETVAL

unsigned int
avs_get_codec_ctx_height(AVCodecContext *c)
    CODE:
        RETVAL = c->height;
    OUTPUT: RETVAL

unsigned int
avs_get_codec_ctx_bitrate(AVCodecContext *c)
    CODE:
        RETVAL = c->bit_rate;
    OUTPUT: RETVAL
    
int
avs_get_codec_ctx_base_den(AVCodecContext *c)
    CODE:
        RETVAL = c->time_base.den;
    OUTPUT: RETVAL

int
avs_get_codec_ctx_base_num(AVCodecContext *c)
    CODE:
        RETVAL = c->time_base.num;
    OUTPUT: RETVAL

int
avs_get_codec_ctx_pixfmt(AVCodecContext *c)
    CODE:
        RETVAL = c->pix_fmt;
    OUTPUT: RETVAL

unsigned int
avs_get_codec_ctx_gopsize(AVCodecContext *c)
    CODE:
        RETVAL = c->gop_size;
    OUTPUT: RETVAL

unsigned int
avs_get_codec_ctx_channels(AVCodecContext *c)
    CODE:
        RETVAL = c->channels;
    OUTPUT: RETVAL

unsigned int
avs_get_codec_ctx_sample_rate(AVCodecContext *c)
    CODE:
        RETVAL = c->sample_rate;
    OUTPUT: RETVAL

unsigned int
avs_get_codec_ctx_frame_delay(AVCodecContext *c)
    CODE:
        RETVAL = av_q2d(c->time_base);
    OUTPUT: RETVAL

int
avs_get_avframe_repeat_pict(AVFrame *f)
    CODE:
        RETVAL = f->repeat_pict;
    OUTPUT: RETVAL

char*
avs_get_avframe_line_pointer(AVFrame *frame, unsigned int y)
    CODE:
        RETVAL = frame->data[0] + y * frame->linesize[0];
    OUTPUT: RETVAL

unsigned int
avs_get_avframe_size(AVFrame *frame, unsigned int line_size, unsigned int height)
    CODE:
    {
        unsigned int frame_size = line_size * height;
        RETVAL = frame_size;
    }
    OUTPUT: RETVAL
    
unsigned int
avs_get_line_size(AVFrame *frame, unsigned int width)
    CODE:
    {
        unsigned int line_size = frame->linesize[0] + frame->linesize[1] 
            + frame->linesize[2] + frame->linesize[3] * width;

        RETVAL = line_size;
    }
    OUTPUT: RETVAL

SV*
avs_get_avframe_data(AVFrame *frame, unsigned int width, unsigned int height, unsigned int line_size, unsigned int frame_size)
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

# attempt to guess the format from the filename (and format if supplied)
AVOutputFormat*
avs_find_output_format(char *uri, char *format)
    CODE:
    {
        AVOutputFormat *fmt;

        fmt = av_guess_format(format, uri, NULL);
        if (! fmt) {
            XSRETURN_UNDEF;
        }

        RETVAL = fmt;
    }
    OUTPUT: RETVAL

AVFormatContext*
avs_create_output_format_ctx(AVOutputFormat *ofmt, char *uri)
    PREINIT:
        AVFormatContext *ctx;
    CODE:
    {
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

        ctx->max_delay = (int)(mux_max_delay*AV_TIME_BASE);

        RETVAL = ctx;
     }
     OUTPUT: RETVAL

void
avs_close_output_format_ctx(AVFormatContext *ctx)
    CODE:
    {
        /* close file if open */
        if (! (ctx->oformat->flags & AVFMT_NOFILE)) {
            avio_close(ctx->pb);
        }
    }

void
avs_dealloc_stream(AVStream *stream)
    CODE:
        av_freep(&stream);

void
avs_set_ctx_metadata(AVFormatContext *ctx, const char *key, const char *value)
    CODE:
        av_dict_set(&ctx->metadata, key, value, 0);
    
void
avs_write_header_and_metadata(AVFormatContext *ctx)
    CODE:
    {
        avformat_write_header(ctx, &ctx->metadata);
        av_dict_free(&ctx->metadata);
    }

void
avs_write_trailer(AVFormatContext *ctx)
    CODE:
        av_write_trailer(ctx);

AVStream*
avs_create_stream(AVFormatContext *ofmt)
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
avs_copy_stream_params(AVFormatContext *ofmt, AVStream *istream, AVStream *ostream)
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
              ocodec->audio_service_type = icodec->audio_service_type;
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
                 if (!ocodec->sample_aspect_ratio.num) {
                     ocodec->sample_aspect_ratio =
                     ostream->sample_aspect_ratio =
                         istream->sample_aspect_ratio.num ? istream->sample_aspect_ratio :
                         istream->codec->sample_aspect_ratio.num ?
                         istream->codec->sample_aspect_ratio : (AVRational){0, 1};
                 }
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
avs_set_video_stream_params(AVFormatContext *ofmt, AVStream *vs, const char *codec_name, unsigned short stream_copy, unsigned int width, unsigned int height, unsigned int bitrate, int base_num, int base_den, unsigned int gopsize, int pixfmt)
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

        /* FIXME: set video stream frame rate to match. */
        vs->r_frame_rate.num = base_num;
        vs->r_frame_rate.den = base_den;

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
avs_set_audio_stream_params(AVFormatContext *ofmt, AVStream *as, const char *codec_name, unsigned short stream_copy, unsigned int channels, unsigned int sample_rate, unsigned int bit_rate)
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
avs_new_output_audio_stream(AVFormatContext *ctx, unsigned int sample_rate, unsigned int bit_rate)
    CODE:
    {        
        int i;
                
        /* find codec */
        /* we should probably pass desired audio codec in here */
        if (ctx->oformat->audio_codec == CODEC_ID_NONE)
            XSRETURN_UNDEF;

        /* find encoder for codec */
        AVCodec *codec = avcodec_find_encoder(ctx->oformat->audio_codec);
        if (! codec) {
            fprintf(stderr, "failed to find encoder");
            XSRETURN_UNDEF;
        }

        /* create codec context, sets default values */
        AVCodecContext *c = avcodec_alloc_context3(codec);
        
        /* open encoder */
        int res = avcodec_open2(c, codec, NULL);
        if (res != 0) {
            fprintf(stderr, "failed to open codec, code: %d\n", res);
            XSRETURN_UNDEF;
        }

        /* create new audio stream */
        AVStream *as = avformat_new_stream(ctx, codec);
        if (! as) {
            XSRETURN_UNDEF;
        }
        
        as->stream_copy = 1;
            
        av_dump_format(ctx, 0, "output", 1);
            
        RETVAL = as;
    }
    OUTPUT: RETVAL

void
avs_close_stream(AVFormatContext *ctx, AVStream *stream)
    CODE:
        avcodec_close(stream->codec);

# dumps information about the context to stderr
void
avs_dump_format(AVFormatContext *ctx, char *title)
    CODE:
        av_dump_format(ctx, 0, title, false);

void
avs_close_input_file(AVFormatContext *ctx)
    CODE:
        av_close_input_file(ctx);

void
avs_destroy_context(AVFormatContext *ctx)
    CODE:
        av_free(ctx);

AVSFrameBuffer*
avs_alloc_output_buffer(unsigned int size)
    CODE:
        RETVAL = av_mallocz(size);
    OUTPUT: RETVAL


# borrowed from libav cmdutils
void
avs_destroy_pts_correction_context(AVFormatContext *ctx)
    CODE:
        av_free(ctx);

PtsCorrectionContext*
avs_alloc_and_init_pts_correction_context()
    CODE:
    {
        PtsCorrectionContext *pcc = av_mallocz(sizeof(PtsCorrectionContext));
        init_pts_correction(pcc);
        RETVAL = pcc;
    }
    OUTPUT: RETVAL



