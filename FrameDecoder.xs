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
typedef struct AVFormatContext FD_AVFormatCtx;
typedef struct AVCodecContext  FD_AVCodecCtx;
typedef struct AVFrame         FD_AVFrame;
typedef struct AVStream        FD_AVStream;
typedef struct AVFormatContext FD_AVOutputFormat;
typedef uint8_t                FD_FrameBuffer;
typedef short bool_t;

#define FD_DEFAULT_PIXFMT PIX_FMT_YUV420P

#pragma mark globals
pthread_mutex_t AVFormatCtxMP;

MODULE = Video::FFmpeg::FrameDecoder		PACKAGE = Video::FFmpeg::FrameDecoder
PROTOTYPES: ENABLE

#pragma mark boot
BOOT:
{
    av_register_all();
    pthread_mutex_init(&AVFormatCtxMP, NULL);
}

#pragma mark methods

FD_AVFormatCtx*
ffv_fd_open_uri(uri)
char* uri;
    CODE:
    {
        /* ffv_fd_open_uri: wrapper around av_open_input_file */

        int lock_status;

        /* use a mutex protect opening a file. I assume this is
         reqiuired because Video::FFmpeg does it */

        lock_status = pthread_mutex_lock(&AVFormatCtxMP);
        if ( lock_status != 0 ) {
            croak("Unable to lock mutex AVFormatCtxMP for %s: %s", uri, sys_errlist[lock_status]);
        };

        FD_AVFormatCtx *formatCtx;

        if ( av_open_input_file(&formatCtx, uri, NULL, 0, NULL) != 0 )
            XSRETURN_UNDEF;
        else
            RETVAL = formatCtx;

        /* make sure we can read the stream */
        if ( av_find_stream_info(formatCtx) < 0 )
            XSRETURN_UNDEF;

        /* unlock mutex */
        lock_status = pthread_mutex_unlock(&AVFormatCtxMP);
        if ( lock_status != 0 ) {
            croak("Unable to unlock mutex AVFormatCtxMP for %s: %s", uri, sys_errlist[lock_status]);
        };
    }
    OUTPUT: RETVAL

unsigned int
ffv_fd_find_first_video_stream_index(ctx)
FD_AVFormatCtx* ctx;
    CODE:
    {
        /* given a context, look for the first video stream inside of
         it. returns stream index or -1 */
         

        int video_stream = -1;
        int i;

        for ( i = 0; i < ctx->nb_streams; i++ ) {
            if ( ctx->streams[i]->codec->codec_type==CODEC_TYPE_VIDEO ) {
                video_stream = i;
                break;
            }
        }
        
        RETVAL = video_stream;
    }
    OUTPUT: RETVAL

FD_AVCodecCtx*
ffv_fd_get_stream(ctx, idx)
int idx;
FD_AVFormatCtx* ctx;
    CODE:
    {
        /* get a stream from a format context by index.
        returns a pointer to the stream codec context or NULL */
        
        /* look up codec object */
        FD_AVCodecCtx *codec_ctx = ctx->streams[idx]->codec;
        RETVAL = codec_ctx;
    }
    OUTPUT: RETVAL

FD_AVFrame*
ffv_fd_alloc_frame()
    CODE:
    {
        /* allocate space for an AVFrame struct */
        RETVAL = avcodec_alloc_frame();
    }
    OUTPUT: RETVAL

void
ffv_fd_dealloc_frame(frame)
FD_AVFrame* frame;
    CODE:
    {
        /* dellocate frame storage */
        av_free(frame);
    }
    
void
ffv_fd_dealloc_frame_buffer(buf)
FD_FrameBuffer* buf;
    CODE:
    {
        /* dellocate frame buffer storage */
        free(buf);
    }

FD_FrameBuffer*
ffv_fd_alloc_frame_buffer(codec_ctx, dst_frame, pixformat)
FD_AVCodecCtx* codec_ctx;
FD_AVFrame* dst_frame;
int pixformat;
    CODE:
    {
        unsigned int size;
        FD_FrameBuffer *buf;
                
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


bool_t
ffv_fd_open_codec(codec_ctx)
FD_AVCodecCtx* codec_ctx;
    CODE:
    {
        /* ffv_fd_open_codec(codec_ctx) attempts to find a decoder for this
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
ffv_fd_close_codec(codec_ctx)
FD_AVCodecCtx* codec_ctx;
    CODE:
    {
        avcodec_close(codec_ctx);
    }

bool_t
ffv_fd_decode_frames(format_ctx, codec_ctx, stream_index, dest_pixfmt, src_frame, dst_frame, dst_frame_buffer, frame_count, decoded_cb)
FD_AVFormatCtx* format_ctx;
FD_AVCodecCtx* codec_ctx;
unsigned int stream_index;
int dest_pixfmt;
FD_AVFrame* src_frame;
FD_AVFrame* dst_frame;
FD_FrameBuffer* dst_frame_buffer;
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

unsigned int
ffv_fd_get_codec_ctx_width(c)
FD_AVCodecCtx* c;
    CODE:
        RETVAL = c->width;
    OUTPUT: RETVAL

unsigned int
ffv_fd_get_codec_ctx_height(c)
FD_AVCodecCtx* c;
    CODE:
        RETVAL = c->height;
    OUTPUT: RETVAL

unsigned int
ffv_fd_get_codec_ctx_bitrate(c)
FD_AVCodecCtx* c;
    CODE:
        RETVAL = c->bit_rate;
    OUTPUT: RETVAL
    
int
ffv_fd_get_codec_ctx_base_den(c)
FD_AVCodecCtx* c;
    CODE:
        RETVAL = c->time_base.den;
    OUTPUT: RETVAL

int
ffv_fd_get_codec_ctx_base_num(c)
FD_AVCodecCtx* c;
    CODE:
        RETVAL = c->time_base.num;
    OUTPUT: RETVAL

int
ffv_fd_get_codec_ctx_pixfmt(c)
FD_AVCodecCtx* c;
    CODE:
        RETVAL = c->pix_fmt;
    OUTPUT: RETVAL

unsigned int
ffv_fd_get_codec_ctx_gopsize(c)
FD_AVCodecCtx* c;
    CODE:
        RETVAL = c->gop_size;
    OUTPUT: RETVAL

char*
ffv_fd_get_frame_line_pointer(frame, y)
FD_AVFrame* frame;
unsigned int y;
    CODE:
    {
        RETVAL = frame->data[0] + y * frame->linesize[0];
    }
    OUTPUT: RETVAL

unsigned int
ffv_fd_get_frame_size(frame, line_size, height)
FD_AVFrame* frame;
unsigned int line_size;
unsigned int height;
    CODE:
    {
        unsigned int frame_size = line_size * height;

        RETVAL = frame_size;
    }
    OUTPUT: RETVAL
    
unsigned int
ffv_fd_get_line_size(frame, width)
FD_AVFrame* frame;
unsigned int width;
    CODE:
    {
        unsigned int line_size = frame->linesize[0] + frame->linesize[1] 
            + frame->linesize[2] + frame->linesize[3] * width;

        RETVAL = line_size;
    }
    OUTPUT: RETVAL

SV*
ffv_fd_get_frame_data(frame, width, height, line_size, frame_size)
FD_AVFrame* frame;
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

FD_AVFormatCtx*
ffv_fd_new_output_format_ctx(filename)
char* filename;
    CODE:
    {
        FD_AVFormatCtx *ctx;

        AVOutputFormat *fmt;

        /* attempt to guess the format using filename as format shortname */
        fmt = av_guess_format(filename, NULL, NULL);

        if (! fmt) {
           /* attempt to guess the format from the filename */
           fmt = av_guess_format(NULL, filename, NULL);
           if (! fmt) {
               fprintf(stderr, "Unable to guess format from filename %s\n", filename);
               XSRETURN_UNDEF;
           }
       }
        
        ctx = avformat_alloc_context();
        if (! ctx)
            XSRETURN_UNDEF;
        
        ctx->oformat = fmt;
        snprintf(ctx->filename, sizeof(ctx->filename), "%s", filename);

        if (! (fmt->flags & AVFMT_NOFILE)) {
            if (url_fopen(&ctx->pb, filename, URL_WRONLY) < 0) {
                fprintf(stderr, "Could not open '%s'\n", filename);
                XSRETURN_UNDEF;
            }
        }

        av_set_parameters(ctx, NULL);
        
        RETVAL = ctx;
     }
     OUTPUT: RETVAL

void
ffv_fd_close_output_format_ctx(ctx)
FD_AVFormatCtx* ctx;
    CODE:
    {
        unsigned int i;
        
        /* free streams */
        for (i = 0; i < ctx->nb_streams; i++) {
            av_freep(&ctx->streams[i]->codec);
            av_freep(&ctx->streams[i]);
        }

        /* close file if open */
        if (! (ctx->oformat->flags & AVFMT_NOFILE)) {
            url_fclose(ctx->pb);
        }
    }
    
void
ffv_fd_write_header(ctx)
FD_AVFormatCtx* ctx;
    CODE:
    {
        av_write_header(ctx);
        av_metadata_free(&ctx->metadata);
    }

void
ffv_fd_write_trailer(ctx)
FD_AVFormatCtx* ctx;
    CODE:
    {
        av_write_trailer(ctx);
    }    

FD_AVStream*
ffv_fd_new_output_video_stream(ctx, width, height, bitrate, base_num, base_den, pixfmt, gopsize)
FD_AVFormatCtx* ctx;
unsigned int width;
unsigned int height;
unsigned int bitrate;
int base_num;
int base_den;
int pixfmt;
unsigned int gopsize;
    CODE:
    {
        FD_AVStream *vs = NULL;
        int i;

        pixfmt = FD_DEFAULT_PIXFMT;
                
        if (ctx->oformat->video_codec == CODEC_ID_NONE)
            XSRETURN_UNDEF;
        
        AVCodecContext *c;
        vs = av_new_stream(ctx, 0);
        if (! vs) {
            return;
        }
        
        vs->stream_copy = 1;
        
        printf("\nwidth: %d, height: %d, bitrate: %u, framerate: %i/%i, timebase: %i/%i, pixfmt: %d, gopsize: %d\n",
            width, height, bitrate, vs->r_frame_rate.num, vs->r_frame_rate.den, base_num, base_den, pixfmt, gopsize);


        c = vs->codec;
        c->codec_id = ctx->oformat->video_codec;
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

        if (c->codec_id == CODEC_ID_MPEG1VIDEO) {
            c->mb_decision = 2;
        }

        /* some formats want stream headers to be separate */
        if (ctx->oformat->flags & AVFMT_GLOBALHEADER)
            c->flags |= CODEC_FLAG_GLOBAL_HEADER;
            
        /* open video stream codec */
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

        RETVAL = vs;
    }
    OUTPUT: RETVAL
    
int
ffv_fd_write_frame_to_output_video_stream(format_ctx, src_codec_ctx, stream, frame)
FD_AVFormatCtx* format_ctx;
FD_AVCodecCtx*  src_codec_ctx;
FD_AVStream*    stream;
FD_AVFrame*     frame;
    CODE:
    {
        unsigned int out_size;
        char *video_outbuf;
        unsigned int video_outbuf_size;
        AVPacket pkt;
        FD_AVCodecCtx *dest_codec_ctx;
        
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
            if (dest_codec_ctx->coded_frame->pts != AV_NOPTS_VALUE)
                pkt.pts = av_rescale_q(dest_codec_ctx->coded_frame->pts, 
                dest_codec_ctx->time_base, stream->time_base);

            if (dest_codec_ctx->coded_frame->key_frame) {
                pkt.flags |= AV_PKT_FLAG_KEY;
            }

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

void
ffv_fd_close_video_stream(ctx, stream)
FD_AVFormatCtx* ctx;
FD_AVStream* stream;
    CODE:
    {
        avcodec_close(stream->codec);
    }

void
ffv_fd_dump_format(ctx, title)
FD_AVFormatCtx* ctx;
char* title;
    CODE:
    {
        /* dumps information about the context to stderr */
        dump_format(ctx, 0, title, false);
    }

void
ffv_fd_destroy_context(ctx)
FD_AVFormatCtx* ctx;
    CODE:
    {
        /* destroy a context */
        av_close_input_file(ctx);
    }
