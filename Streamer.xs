#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"

#include "ppport.h"

#include <libavformat/avformat.h>
#include <libavutil/pixfmt.h>
#include <libswscale/swscale.h>
#include <pthread.h>
#include <stdio.h>
#include <stdlib.h>
#include <stdbool.h>

#pragma mark types
typedef uint8_t                FFS_FrameBuffer;
typedef short bool_t;

#define FFS_DEFAULT_PIXFMT PIX_FMT_YUV420P
static float mux_preload   = 0.5;
static float mux_max_delay = 0.7;

#pragma mark globals
pthread_mutex_t AVFormatCtxMP;

MODULE = Video::FFmpeg::Streamer		PACKAGE = Video::FFmpeg::Streamer
PROTOTYPES: ENABLE

#pragma mark boot
BOOT:
{
    av_register_all();
    pthread_mutex_init(&AVFormatCtxMP, NULL);
}

#pragma mark methods

AVFormatContext*
ffs_open_uri(uri)
char* uri;
    CODE:
    {
        /* ffs_open_uri: wrapper around av_open_input_file */

        int lock_status;

        /* use a mutex protect opening a file. I assume this is
         reqiuired because Video::FFmpeg does it */

        lock_status = pthread_mutex_lock(&AVFormatCtxMP);
        if ( lock_status != 0 ) {
            croak("Unable to lock mutex AVFormatCtxMP for %s: %s", uri, sys_errlist[lock_status]);
        };

        AVFormatContext *formatCtx;

        if ( av_open_input_file(&formatCtx, uri, NULL, 0, NULL) != 0 )
            XSRETURN_UNDEF;
        else
            RETVAL = formatCtx;

        /* make sure we can read the stream */
        if ( av_find_stream_info(formatCtx) < 0 ) {
            fprintf("Failed to find codec parameters for input %s\n", uri);
            XSRETURN_UNDEF;
        }

        /* unlock mutex */
        lock_status = pthread_mutex_unlock(&AVFormatCtxMP);
        if ( lock_status != 0 ) {
            fprintf(stderr, "Unable to unlock mutex AVFormatCtxMP for %s: %s", uri, sys_errlist[lock_status]);
        };
    }
    OUTPUT: RETVAL

unsigned int
ffs_stream_count(fmt)
AVFormatContext* fmt;
    CODE:
        RETVAL = fmt->nb_streams;
    OUTPUT: RETVAL

unsigned short
ffs_is_video_stream_index(fmt, index)
AVFormatContext* fmt;
unsigned int index;
    CODE:
        RETVAL = fmt->streams[index]->codec->codec_type == CODEC_TYPE_VIDEO;
    OUTPUT: RETVAL

unsigned short
ffs_is_audio_stream_index(fmt, index)
AVFormatContext* fmt;
unsigned int index;
    CODE:
        RETVAL = fmt->streams[index]->codec->codec_type == CODEC_TYPE_AUDIO;
    OUTPUT: RETVAL

unsigned short
ffs_is_video_stream(stream)
AVStream* stream;
    CODE:
        RETVAL = stream->codec->codec_type == CODEC_TYPE_VIDEO;
    OUTPUT: RETVAL

unsigned short
ffs_is_audio_stream(stream)
AVStream* stream;
    CODE:
        RETVAL = stream->codec->codec_type == CODEC_TYPE_AUDIO;
    OUTPUT: RETVAL


unsigned int
ffs_get_stream_index(stream)
AVStream* stream;
    CODE:
        RETVAL = stream->index;
    OUTPUT: RETVAL

AVStream*
ffs_get_stream(ctx, idx)
AVFormatContext* ctx;
int idx;
    CODE:
    {
        /* get a stream from a format context by index.
        returns a pointer to the stream context or NULL */
        
        /* look up codec object */
        AVStream *stream = ctx->streams[idx];
        if (! stream) XSRETURN_UNDEF;

        RETVAL = stream;
    }
    OUTPUT: RETVAL

AVFrame*
ffs_alloc_frame()
    CODE:
    {
        /* allocate space for an AVFrame struct */
        RETVAL = avcodec_alloc_frame();
    }
    OUTPUT: RETVAL

void
ffs_dealloc_frame(frame)
AVFrame* frame;
    CODE:
    {
        /* dellocate frame storage */
        av_free(frame);
    }
    
void
ffs_dealloc_frame_buffer(buf)
FFS_FrameBuffer* buf;
    CODE:
    {
        /* dellocate frame buffer storage */
        free(buf);
    }

FFS_FrameBuffer*
ffs_alloc_frame_buffer(codec_ctx, dst_frame, pixformat)
AVCodecContext* codec_ctx;
AVFrame* dst_frame;
int pixformat;
    CODE:
    {
        unsigned int size;
        FFS_FrameBuffer *buf;
                
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
ffs_get_codec_ctx(stream)
AVStream* stream;
    CODE:
        RETVAL = stream->codec;
    OUTPUT: RETVAL

bool_t
ffs_open_codec(codec_ctx)
AVCodecContext* codec_ctx;
    CODE:
    {
        /* ffs_open_codec(codec_ctx) attempts to find a decoder for this
         codec and open it. returns success/failure */

        /* find the decoder for the video stream */
        AVCodec *codec = avcodec_find_decoder(codec_ctx->codec_id);
        if ( codec == NULL ) {
            /* could not find a decoder for this codec */
            RETVAL = 0;
            return;
        }

        /* open codec */
        if ( avcodec_open(codec_ctx, codec) < 0 ) {
            /* failed to open the codec */
            RETVAL = 0;
            return;
        }

        RETVAL = 1;
    }
    OUTPUT: RETVAL

void
ffs_close_codec(codec_ctx)
AVCodecContext* codec_ctx;
    CODE:
    {
        avcodec_close(codec_ctx);
    }

bool_t
ffs_decode_frames(format_ctx, codec_ctx, stream_index, dest_pixfmt, src_frame, dst_frame, dst_frame_buffer, frame_count, decoded_cb)
AVFormatContext* format_ctx;
AVCodecContext* codec_ctx;
unsigned int stream_index;
int dest_pixfmt;
AVFrame* src_frame;
AVFrame* dst_frame;
FFS_FrameBuffer* dst_frame_buffer;
unsigned int frame_count;
CV* decoded_cb;
    CODE:
    {
        AVPacket packet;
        unsigned int frameFinished, w, h;
        unsigned int frame = 0;
        struct SwsContext *img_convert_ctx = NULL;
        
        while( av_read_frame(format_ctx, &packet) >= 0 ) {
            if (packet.stream_index != stream_index)
                continue;
            
            avcodec_decode_video(codec_ctx, src_frame, &frameFinished, 
                packet.data, packet.size);

            if (! frameFinished) 
                continue;
                
            if (img_convert_ctx == NULL) {
                w = codec_ctx->width;
                h = codec_ctx->height;
                
                /* create context to convert to dest pixformat */
                img_convert_ctx = sws_getContext(w, h, 
                				codec_ctx->pix_fmt, 
                				w, h, dest_pixfmt, SWS_BICUBIC,
                				NULL, NULL, NULL);

                if (img_convert_ctx == NULL) {
                    RETVAL = 0;
                	fprintf(stderr, "Cannot initialize the conversion context!\n");
                	av_free_packet(&packet);
                    return;
                }
			}
			
            sws_scale(img_convert_ctx, src_frame->data, src_frame->linesize, 0, 
                codec_ctx->height, dst_frame->data, dst_frame->linesize);
                
            /* we now have a decoded frame */
            frame++;
            if (frame_count && frame > frame_count)
                break;
            
            /* call perl CV callback */
        	dSP;
        	ENTER;
        	SAVETMPS;
        	PUSHMARK(SP);
        	XPUSHs( sv_2mortal( newSVuv( frame )));
        	XPUSHs( sv_2mortal( newSVuv( codec_ctx->width )));
        	XPUSHs( sv_2mortal( newSVuv( codec_ctx->height )));
        	PUTBACK;

        	call_sv( decoded_cb, G_DISCARD );
	
        	FREETMPS;
        	LEAVE;
        }
        
        av_free_packet(&packet);
    }
    OUTPUT: RETVAL

AVCodec*
ffs_get_codec_ctx_codec(c)
AVCodecContext* c;
    CODE:
        RETVAL = c->codec;
    OUTPUT: RETVAL

const char*
ffs_get_codec_ctx_codec_name(c)
AVCodecContext* c;
    CODE:
        RETVAL = c->codec->name;
    OUTPUT: RETVAL

unsigned int
ffs_get_codec_ctx_width(c)
AVCodecContext* c;
    CODE:
        RETVAL = c->width;
    OUTPUT: RETVAL

unsigned int
ffs_get_codec_ctx_height(c)
AVCodecContext* c;
    CODE:
        RETVAL = c->height;
    OUTPUT: RETVAL

unsigned int
ffs_get_codec_ctx_bitrate(c)
AVCodecContext* c;
    CODE:
        RETVAL = c->bit_rate;
    OUTPUT: RETVAL
    
int
ffs_get_codec_ctx_base_den(c)
AVCodecContext* c;
    CODE:
        RETVAL = c->time_base.den;
    OUTPUT: RETVAL

int
ffs_get_codec_ctx_base_num(c)
AVCodecContext* c;
    CODE:
        RETVAL = c->time_base.num;
    OUTPUT: RETVAL

int
ffs_get_codec_ctx_pixfmt(c)
AVCodecContext* c;
    CODE:
        RETVAL = c->pix_fmt;
    OUTPUT: RETVAL

unsigned int
ffs_get_codec_ctx_gopsize(c)
AVCodecContext* c;
    CODE:
        RETVAL = c->gop_size;
    OUTPUT: RETVAL

char*
ffs_get_frame_line_pointer(frame, y)
AVFrame* frame;
unsigned int y;
    CODE:
    {
        RETVAL = frame->data[0] + y * frame->linesize[0];
    }
    OUTPUT: RETVAL

unsigned int
ffs_get_frame_size(frame, line_size, height)
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
ffs_get_line_size(frame, width)
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
ffs_get_frame_data(frame, width, height, line_size, frame_size)
AVFrame* frame;
unsigned int width;
unsigned int height;
unsigned int line_size;
unsigned int frame_size;
    CODE:
    {
        char *buf, *offset;
        unsigned int y;

        buf = av_mallocz(frame_size);
        
        offset = buf;
        for ( y = 0; y < height; y++ ) {
            memcpy(offset, frame->data[0] + y * frame->linesize[0], line_size);
            offset += line_size;
        }

        SV *ret = newSVpv(buf, frame_size);
        free(buf);
        
        RETVAL = ret;
    }
    OUTPUT: RETVAL

AVOutputFormat*
ffs_find_output_format(uri, format)
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
ffs_create_output_format_ctx(ofmt, uri)
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
        /* open output file for writing (if applicable)
        if (! (fmt->flags & AVFMT_NOFILE)) {
            if (url_fopen(&ctx->pb, uri, URL_WRONLY) < 0) {
                fprintf(stderr, "Could not open '%s' for writing\n", uri);
                XSRETURN_UNDEF;
            }
        }

        /* TODO: copy metadata from input? */

        ctx->preload   = (int)(mux_preload*AV_TIME_BASE);
        ctx->max_delay = (int)(mux_max_delay*AV_TIME_BASE);

        /* TODO: allow encoding params to be specified */
        av_set_parameters(ctx, NULL);
        
        RETVAL = ctx;
     }
     OUTPUT: RETVAL

void
ffs_close_output_format_ctx(ctx)
AVFormatContext* ctx;
    CODE:
    {
        /* close file if open */
        if (! (ctx->oformat->flags & AVFMT_NOFILE)) {
            url_fclose(ctx->pb);
        }
    }

void
ffs_destroy_stream(stream)
AVStream* stream;
    CODE:
    {
//        if (stream->codec)
//            av_freep(&stream->codec);

        av_freep(&stream);
    }

void
ffs_set_ctx_metadata(ctx, key, value)
AVFormatContext* ctx;
const char* key;
const char* value;
    CODE:
    {
        av_metadata_set2(&ctx->metadata, key, value, 0);
    }

    
void
ffs_write_header(ctx)
AVFormatContext* ctx;
    CODE:
    {
        av_write_header(ctx);
        av_metadata_free(&ctx->metadata);
    }

void
ffs_write_trailer(ctx)
AVFormatContext* ctx;
    CODE:
    {
        av_write_trailer(ctx);
    }    

AVStream*
ffs_create_video_stream(fmt, codec_name, stream_copy, width, height, bitrate, base_num, base_den, gopsize, pixfmt)
AVFormatContext* fmt;
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
        AVStream *vs = NULL;
        int i;

        if (! pixfmt)
            pixfmt = FFS_DEFAULT_PIXFMT;
                
        if (! codec_name && fmt->oformat->video_codec == CODEC_ID_NONE)
            XSRETURN_UNDEF;

        vs = av_new_stream(fmt, 0);
        if (! vs) {
            XSRETURN_UNDEF;
        }

        vs->stream_copy = stream_copy;

        AVCodecContext *c = vs->codec;

        if (codec_name) {
            AVCodec *output_codec = avcodec_find_encoder_by_name(codec_name);
            c->codec = output_codec;
        } else {
            c->codec_id = fmt->oformat->video_codec;
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
        //c->pix_fmt = pixfmt;

        printf("\nwidth: %d, height: %d, bitrate: %u, framerate: %i/%i, timebase: %i/%i, pixfmt: %d, gopsize: %d\n",
            width, height, bitrate, vs->r_frame_rate.num, vs->r_frame_rate.den, base_num, base_den, pixfmt, gopsize);

        if (c->codec_id == CODEC_ID_MPEG1VIDEO) {
            c->mb_decision = 2;
        }

        /* some formats want stream headers to be separate */
        if (fmt->oformat->flags & AVFMT_GLOBALHEADER)
            c->flags |= CODEC_FLAG_GLOBAL_HEADER;
            
        /* open video stream codec */
        AVCodec *codec;
        codec = avcodec_find_encoder(c->codec_id);
        if (! codec) {
            fprintf(stderr, "failed to find encoder");
            return;
        }
            
        dump_format(fmt, 0, "output", 1);
            
        if (avcodec_open(c, codec) < 0) {
            fprintf(stderr, "failed to open codec");
            return;
        }

        RETVAL = vs;
    }
    OUTPUT: RETVAL
    
int
ffs_write_frame_to_output_video_stream(format_ctx, src_codec_ctx, stream, frame)
AVFormatContext* format_ctx;
AVCodecContext*  src_codec_ctx;
AVStream*    stream;
AVFrame*     frame;
    CODE:
    {
        unsigned int out_size;
        char *video_outbuf;
        unsigned int video_outbuf_size;
        AVPacket pkt;
        AVCodecContext *dest_codec_ctx;
        
        dest_codec_ctx = stream->codec;

        /* buffer size taken from ffmpeg sample output program.
           not sure about this. to speed things up we should save the output 
           buffer rather than reallocating it each frame. */
        video_outbuf_size = 200000;
        video_outbuf = av_mallocz(video_outbuf_size);
        
        RETVAL = 0;
        
        out_size = avcodec_encode_video(dest_codec_ctx, video_outbuf, video_outbuf_size, frame);
        
        /* if zero size, it means the image was buffered */
        if (out_size > 0) {
            av_init_packet(&pkt);

            /* no idea what this is! */
            if (dest_codec_ctx->coded_frame->pts != AV_NOPTS_VALUE) {
                pkt.pts = av_rescale_q(dest_codec_ctx->coded_frame->pts, 
                dest_codec_ctx->time_base, stream->time_base);
            }

            if (dest_codec_ctx->coded_frame->key_frame)
                pkt.flags |= AV_PKT_FLAG_KEY;

            pkt.stream_index = stream->index;
            pkt.data = video_outbuf;
            pkt.size = out_size;
            
            /* write the compressed frame in the media file */
            RETVAL = av_interleaved_write_frame(format_ctx, &pkt);
        } else {
            RETVAL = 1;
        }

        av_free(video_outbuf);
    }
    OUTPUT: RETVAL

AVStream*
ffs_new_output_audio_stream(ctx, sample_rate, bit_rate)
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

        dump_format(ctx, 0, "output", 1);
            
        if (avcodec_open(c, codec) < 0) {
            fprintf(stderr, "failed to open codec");
            return;
        }

        RETVAL = as;
    }
    OUTPUT: RETVAL
    
int
ffs_write_frame_to_output_audio_stream(format_ctx, src_codec_ctx, stream, frame)
AVFormatContext* format_ctx;
AVCodecContext*  src_codec_ctx;
AVStream*    stream;
AVFrame*     frame;
    CODE:
    {
        unsigned int out_size;
        char *audio_outbuf;
        unsigned int audio_outbuf_size;
        AVPacket pkt;
        AVCodecContext *dest_codec_ctx;
        
        dest_codec_ctx = stream->codec;

        audio_outbuf_size = 200000;
        audio_outbuf = av_mallocz(audio_outbuf_size);
        
        RETVAL = 0;
        
        out_size = avcodec_encode_audio(dest_codec_ctx, audio_outbuf, audio_outbuf_size, frame);
        
        /* if zero size, it means the image was buffered */
        if (out_size > 0) {
            av_init_packet(&pkt);

            /* no idea what this is! */
            if (dest_codec_ctx->coded_frame && dest_codec_ctx->coded_frame->pts != AV_NOPTS_VALUE) {
                pkt.pts = av_rescale_q(dest_codec_ctx->coded_frame->pts, 
                                       dest_codec_ctx->time_base, stream->time_base);
            }

            pkt.stream_index = stream->index;
            pkt.data = audio_outbuf;
            pkt.size = out_size;
            
            /* write the compressed frame in the media file */
            RETVAL = av_interleaved_write_frame(format_ctx, &pkt);
        } else {
            RETVAL = 1;
        }

        av_free(audio_outbuf);
    }
    OUTPUT: RETVAL

void
ffs_close_stream(ctx, stream)
AVFormatContext* ctx;
AVStream* stream;
    CODE:
    {
        avcodec_close(stream->codec);
    }

void
ffs_dump_format(ctx, title)
AVFormatContext* ctx;
char* title;
    CODE:
    {
        /* dumps information about the context to stderr */
        dump_format(ctx, 0, title, false);
    }

void
ffs_destroy_context(ctx)
AVFormatContext* ctx;
    CODE:
    {
        /* destroy a context */
        av_close_input_file(ctx);
    }
