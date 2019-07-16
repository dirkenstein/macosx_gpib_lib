/*
 * Copyright (c) 2004 Frank Mori Hess (fmhess@users.sourceforge.net)
 * Copyright (c) 2018 Guilhem Vavelin (guileukow@users.sourceforge.net)
 *
 *    This source code is free software; you can redistribute it
 *    and/or modify it in source code form under the terms of the GNU
 *    General Public License as published by the Free Software
 *    Foundation; either version 2 of the License, or (at your option)
 *    any later version.
 *
 *    This program is distributed in the hope that it will be useful,
 *    but WITHOUT ANY WARRANTY; without even the implied warranty of
 *    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 *    GNU General Public License for more details.
 *
 *    You should have received a copy of the GNU General Public License
 *    along with this program; if not, write to the Free Software
 *    Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA 02111-1307, USA
 */

#import <Foundation/Foundation.h>
#import "Agilent_82357_AB.h"
#import "ezusb.h"

UInt8 verbose = 0;
/*
 * \brief  Callback function for ReadPipeAsync and WritePipeAxync
 *
 * This function retrieves the read or written amount of data
 * then it set the read/write flag to YES and wake up the waiting
 * RunLoop.
 */
static void bulk_complete(void * refCon, IOReturn result, void * arg0)
{
    bulk_context *context =  (bulk_context *) refCon;
    context->actual_length = (UInt32) arg0;
    context->result = result;
    if(result == kIOReturnTimeout)
        context->timed_out = YES;
    context->triggered = YES;
    CFRunLoopSourceSignal(context->complete);
    /*CFRunLoopWakeUp(context->runner) is optional but recommendend with CFRunLoopSourceSignal version 0 */
    CFRunLoopWakeUp(context->runner);
}

/*
 * \brief  Callback function for Interrupt
 *
 * This function monitor bus interrupt and setup a new interrupt
 * monitoring task.
 */
static void interrupt_complete(void * refCon, IOReturn result, void * arg0)
{
    private_data *a_priv = (private_data*)refCon;
    IOReturn retval = 0;
    UInt32 interrupt_flags;
    /* don't resubmit if urb was unlinked */
    if(result != kIOReturnTimeout && result != 0)
    {
        GPIB_DPRINTK("Stopping Interrupt and result is %d", result);
        return;
    }
    else if(result == kIOReturnTimeout)
    {
        /* if a timeout has occured force resynch with the pipe */
        (*a_priv->bus_interface)->ClearPipeStallBothEnds(a_priv->bus_interface,a_priv->interrupt_in_endpoint);
    }
    interrupt_flags = a_priv->interrupt_buffer[0];
    if([gpib_board test_bit:AIF_READ_COMPLETE_BN : &interrupt_flags])
        [gpib_board set_bit:AIF_READ_COMPLETE_BN : &a_priv->interrupt_flags];
    if([gpib_board test_bit:AIF_WRITE_COMPLETE_BN : &interrupt_flags])
        [gpib_board set_bit:AIF_WRITE_COMPLETE_BN : &a_priv->interrupt_flags];
    if([gpib_board test_bit:AIF_SRQ_BN : &interrupt_flags])
        [gpib_board set_bit:SRQI_NUM : &(a_priv->board->status)];
    retval = (*a_priv->bus_interface)->ReadPipeAsync(a_priv->bus_interface, a_priv->interrupt_in_endpoint, a_priv->interrupt_buffer, sizeof(a_priv->interrupt_buffer), &interrupt_complete, a_priv);
    if(retval)
       GPIB_DPRINTK("%s: failed to resubmit interrupt urb\n", __FUNCTION__);
    a_priv->triggered = YES;
    
    CFRunLoopSourceSignal(a_priv->board->wait);
    /*CFRunLoopWakeUp(context->runner) is optional but recommendend with CFRunLoopSourceSignal version 0 */
    CFRunLoopWakeUp(a_priv->board->runner);
}

@implementation agilent_82357_ab

pthread_mutex_t hotplug_lock = PTHREAD_MUTEX_INITIALIZER;

/*
 * \brief  Main function to send data through USB port
 *
 * This function send data asynchronously. Synchronous write has been tested as well
 * but the performance doesn't increase that much.
 */
-(SInt32) send_bulk_msg:(void *) data : (UInt32) data_length : (UInt32 *) actual_data_length : (UInt32) timeout_msecs
{
    SInt32 retval;
    bulk_context context;
    
    *actual_data_length = 0;
    pthread_mutex_lock(&m_bulk_alloc_lock);
    if(m_private.bus_interface == NULL)
    {
        pthread_mutex_unlock(&m_bulk_alloc_lock);
        return -ENODEV;
    }
    context.runner = CFRunLoopGetCurrent();
    context.complete = CFRunLoopSourceCreate(NULL, 0, &m_source_context);
    context.timed_out = NO;
    context.triggered = NO;

    retval = (*m_private.bus_interface)->WritePipeAsyncTO(m_private.bus_interface, m_private.bulk_out_endpoint, data, data_length, timeout_msecs, timeout_msecs, &bulk_complete, &context);
    if(retval)
    {
        GPIB_DPRINTK("%s: failed to submit bulk out urb, retval=%i\n", __FILE__, retval);
        if(retval == kIOReturnTimeout)
        {
            retval = -ETIMEDOUT;
            (*m_private.bus_interface)->ClearPipeStallBothEnds(m_private.bus_interface,m_private.bulk_out_endpoint);
        }
    }
    else
    {
        CFRunLoopRunResult res = 0;
        while(!context.triggered) {
            res = CFRunLoopRunInMode(kCFRunLoopDefaultMode, (timeout_msecs / 1000.0), YES);
            if(res == kCFRunLoopRunTimedOut)
            {
                context.timed_out = YES;
            }
        }
        if(context.timed_out)
        {
            GPIB_DPRINTK("%s timed out", __FUNCTION__);
            retval =-ETIMEDOUT;
        }
        else
            retval = context.result;
        *actual_data_length = context.actual_length;
    }
    pthread_mutex_unlock(&m_bulk_alloc_lock);
    CFRunLoopSourceInvalidate(context.complete);
    CFRelease(context.complete);
    return retval;
}

/*
 * \brief  Main function to read data through USB port
 *
 * This function read data asynchronously. Synchronous write has been tested as well
 * but the performance doesn't increase that much.
 */
-(SInt32) receive_bulk_msg:(void *) data : (UInt32) data_length : (UInt32 *) actual_data_length : (UInt32) timeout_msecs
{
    SInt32 retval;
    bulk_context context;
    *actual_data_length = 0;
    pthread_mutex_lock(&m_bulk_alloc_lock);
    if(m_private.bus_interface == NULL)
    {
        pthread_mutex_unlock(&m_bulk_alloc_lock);
        return -ENODEV;
    }
    context.runner = CFRunLoopGetCurrent();
    context.complete = CFRunLoopSourceCreate(NULL, 0, &m_source_context);
    context.timed_out = NO;
    context.triggered = NO;
    retval = (*m_private.bus_interface)->ReadPipeAsyncTO(m_private.bus_interface, m_private.bulk_in_endpoint, data, data_length, timeout_msecs, timeout_msecs, &bulk_complete, &context);

    if(retval)
    {
        GPIB_DPRINTK("%s: failed to submit bulk out urb, retval=%i\n", __FILE__, retval);
        if(retval == kIOReturnTimeout)
        {   /* if a timeout has occured force resynch with the pipe */
            (*m_private.bus_interface)->ClearPipeStallBothEnds(m_private.bus_interface,m_private.bulk_in_endpoint);
            retval = -ETIMEDOUT;
        }
    }
    else
    {
        CFRunLoopRunResult res = 0;
        while(!context.triggered) {
            res = CFRunLoopRunInMode(kCFRunLoopDefaultMode, (timeout_msecs / 1000.0), YES);
            if(res == kCFRunLoopRunTimedOut)
            {
                context.timed_out = YES;
                timeout_msecs = 1000.0;
            }
        }
        if(context.timed_out)
        {
            GPIB_DPRINTK("%s timed out", __FUNCTION__);
            retval = -ETIMEDOUT;
        }
        else
            retval = context.result;
        *actual_data_length = context.actual_length;
    }
    pthread_mutex_unlock(&m_bulk_alloc_lock);
    CFRunLoopSourceInvalidate(context.complete);
    CFRelease(context.complete);
    return retval;
}

-(SInt32) receive_control_msg:(UInt8) request : (UInt8) requesttype : (UInt16)  value : (UInt16) index : (void *) data : (UInt16) size : (UInt32) timeout_msecs
{
    SInt32 retval;
    UInt8 in_pipe;
    
    retval = pthread_mutex_lock(&m_control_alloc_lock);
    if(retval) return retval;
    if(m_private.bus_interface == NULL)
    {
        pthread_mutex_unlock(&m_control_alloc_lock);
        return -ENODEV;
    }
    in_pipe = AGILENT_82357_CONTROL_ENDPOINT;
    IOUSBDevRequestTO req;
    req.bmRequestType = requesttype;
    req.bRequest = request;
    req.wValue = value;
    req.wIndex = index;
    req.wLength = size;
    req.pData = data;
    req.wLenDone = 0;
    req.completionTimeout = timeout_msecs;
    
    
    retval = (*m_private.bus_interface)->ControlRequestTO(m_private.bus_interface, in_pipe, &req);
    pthread_mutex_unlock(&m_control_alloc_lock);
    return retval;
}

-(void) dump_raw_block:(const UInt8 *) raw_data : (UInt32) length
{
    UInt32 i;
    
    GPIB_DPRINTK("%s:", __FUNCTION__);
    for(i = 0; i < length; ++i)
    {
        if(i % 8 == 0)
            GPIB_DPRINTK("\n");
        GPIB_DPRINTK("%s %2x", __FUNCTION__, raw_data[i]);
    }
    GPIB_DPRINTK("\n");
}

-(SInt32) write_registers:(const struct register_pairlet *) writes : (UInt32) num_writes
{
    SInt32 retval;
    UInt8 *out_data, *in_data;
    UInt32 out_data_length, in_data_length;
    UInt32 bytes_written, bytes_read;
    UInt32 i = 0;
    UInt32 j;
    const UInt16 bytes_per_write = 2;
    const UInt16 header_length = 2;
    const UInt16 max_writes = 31;
    
    if(num_writes > max_writes)
    {
        GPIB_DPRINTK("%s: %s: bug! num_writes=%i too large\n", __FILE__, __FUNCTION__, num_writes);
        return -EIO;
    }
    out_data_length = num_writes * bytes_per_write + header_length;
    out_data = calloc(out_data_length,sizeof(UInt8));
    out_data[i++] = DATA_PIPE_CMD_WR_REGS;
    out_data[i++] = num_writes;
    for(j = 0; j < num_writes; j++)
    {
        out_data[i++] = writes[j].address;
        out_data[i++] = writes[j].value;
    }
    if(i > out_data_length)
    {
        printf("%s: bug! buffer overrun\n", __FUNCTION__);
    }
    retval = pthread_mutex_lock(&m_bulk_transfer_lock);
    if(retval)
    {
        free(out_data);
        return retval;
    }
    retval = [self send_bulk_msg: out_data : i : &bytes_written : 1000];
    free(out_data);
    if(retval)
    {
        GPIB_DPRINTK("%s: %s: send_bulk_msg returned %i, bytes_written=%i, i=%i\n", __FILE__, __FUNCTION__,
              retval, bytes_written, i);
        pthread_mutex_unlock(&m_bulk_transfer_lock);
        return retval;
    }
    in_data_length = 0x20;
    in_data = calloc(in_data_length, sizeof(UInt8));
    retval = [self receive_bulk_msg:in_data : in_data_length : &bytes_read : 1000];
    pthread_mutex_unlock(&m_bulk_transfer_lock);
    if(retval)
    {
        GPIB_DPRINTK("%s: %s: receive_bulk_msg returned %i, bytes_read=%i\n", __FILE__, __FUNCTION__, retval, bytes_read);
        [self dump_raw_block:in_data : bytes_read];
        free(in_data);
        return -EIO;
    }
    if(in_data[0] != (0xff & ~DATA_PIPE_CMD_WR_REGS))
    {
        GPIB_DPRINTK("%s: %s: error, bulk command=0x%x != ~DATA_PIPE_CMD_WR_REGS\n", __FILE__, __FUNCTION__, in_data[0]);
        free(in_data);
        return -EIO;
    }
    if(in_data[1])
    {
        GPIB_DPRINTK("%s: %s: nonzero error code 0x%x in DATA_PIPE_CMD_WR_REGS response\n", __FILE__, __FUNCTION__, in_data[1]);
        free(in_data);
        return -EIO;
    }
    free(in_data);
    return 0;
}

-(SInt32) read_registers:(struct register_pairlet *) reads : (UInt32) num_reads : (BOOL) blocking
{
    SInt32 retval;
    UInt8 *out_data, *in_data;
    UInt32 out_data_length, in_data_length;
    UInt32 bytes_written, bytes_read;
    UInt32 i = 0;
    UInt32 j;
    const UInt32 header_length = 2;
    const UInt32 max_reads = 62;
    
    if(num_reads > max_reads)
    {
        GPIB_DPRINTK("%s: %s: bug! num_reads=%i too large\n", __FILE__, __FUNCTION__, num_reads);
    }
    out_data_length = num_reads + header_length;
    out_data = calloc(out_data_length, sizeof(UInt8));
    out_data[i++] = DATA_PIPE_CMD_RD_REGS;
    out_data[i++] = num_reads;
    for(j = 0; j < num_reads; j++)
    {
        out_data[i++] = reads[j].address;
    }
    if(i > out_data_length)
    {
        GPIB_DPRINTK("%s: bug! buffer overrun\n", __FUNCTION__);
    }
    if(blocking)
    {
        retval = pthread_mutex_lock(&m_bulk_transfer_lock);
        if(retval)
        {
            free(out_data);
            return retval;
        }
        
    }else
    {
        retval = pthread_mutex_trylock(&m_bulk_transfer_lock);
        if(retval)
        {
            free(out_data);
            return -EAGAIN;
        }
    }
    retval = [self send_bulk_msg:out_data : i : &bytes_written : 1000];
    free(out_data);
    if(retval)
    {
        GPIB_DPRINTK("%s: %s: send_bulk_msg returned %i, bytes_written=%i, i=%i\n", __FILE__, __FUNCTION__,
              retval, bytes_written, i);
        pthread_mutex_unlock(&m_bulk_transfer_lock);
        return retval;
    }
    in_data_length = 0x20;
    in_data = calloc(in_data_length,sizeof(UInt8));
    retval = [self receive_bulk_msg:in_data : in_data_length : &bytes_read : 10000];
    pthread_mutex_unlock(&m_bulk_transfer_lock);
    if(retval)
    {
        GPIB_DPRINTK("%s: %s: receive_bulk_msg returned %i, bytes_read=%i\n", __FILE__, __FUNCTION__, retval, bytes_read);
        [self dump_raw_block:in_data : bytes_read];
        free(in_data);
        return -EIO;
    }
    i = 0;
    if(in_data[i++] != (0xff & ~DATA_PIPE_CMD_RD_REGS))
    {
        GPIB_DPRINTK("%s: %s: error, bulk command=0x%x != ~DATA_PIPE_CMD_RD_REGS\n", __FILE__, __FUNCTION__, in_data[0]);
        free(in_data);
        return -EIO;
    }
    if(in_data[i++])
    {
        GPIB_DPRINTK("%s: %s: nonzero error code 0x%x in DATA_PIPE_CMD_RD_REGS response\n", __FILE__, __FUNCTION__, in_data[1]);
        free(in_data);
        return -EIO;
    }
    for(j = 0; j < num_reads; j++)
    {
        reads[j].value = in_data[i++];
    }
    free(in_data);
    return 0;
}

-(SInt32) abort:(BOOL) flush
{
    SInt32 retval;
    UInt16 wIndex = 0;
    UInt8 status_data[2] = {0,0};
    
    if(flush)
        wIndex |= XA_FLUSH;
    retval = [self receive_control_msg:control_request : USB_DIR_IN | USB_TYPE_VENDOR | USB_RECIP_DEVICE : XFER_ABORT : wIndex : status_data : sizeof(status_data) : 100];
    if(retval < 0)
    {
        GPIB_DPRINTK("%s: %s: receive_control_msg() returned %i\n", __FILE__, __FUNCTION__, retval);
        return -EIO;
    }
    if(status_data[0] != (~XFER_ABORT & 0xff))
    {
        GPIB_DPRINTK("%s: %s: error, major code=0x%x != ~XFER_ABORT\n", __FILE__, __FUNCTION__, status_data[0]);
        return -EIO;
    }
    switch(status_data[1])
    {
        case UGP_SUCCESS:
            return 0;
            break;
        case UGP_ERR_FLUSHING:
            if(flush) return 0;
            //fall-through
        case UGP_ERR_FLUSHING_ALREADY:
        default:
            GPIB_DPRINTK("%s: %s: abort returned error code=0x%x\n", __FILE__, __FUNCTION__, status_data[1]);
            return -EIO;
            break;
    }
}

// interface functions
-(SInt32) read:(UInt8 *) buffer : (UInt32) length : (BOOL *) end : (UInt32 *) nbytes_read
{
    SInt32 retval;
    //UInt8 *out_data;//, *in_data;
    UInt8 out_data[9];
    UInt32 /*out_data_length,*/ in_data_length;
    UInt32 bytes_written, bytes_read;
    UInt32 i = 0;
    UInt8 trailing_flags;
    UInt32 msec_timeout;
    *nbytes_read = 0;
    *end = NO;
    //out_data_length = 0x9;
    //out_data = calloc(out_data_length, sizeof(UInt8));
    out_data[i++] = DATA_PIPE_CMD_READ;
    out_data[i++] = 0;	//primary address when ARF_NO_ADDR is not set
    out_data[i++] = 0;	//secondary address when ARF_NO_ADDR is not set
    out_data[i] = ARF_NO_ADDRESS | ARF_END_ON_EOI;
    if(m_eos_mode & REOS)
        out_data[i] |= ARF_END_ON_EOS_CHAR;
    ++i;
    out_data[i++] = length & 0xff;
    out_data[i++] = (length >> 8) & 0xff;
    out_data[i++] = (length >> 16) & 0xff;
    out_data[i++] = (length >> 24) & 0xff;
    out_data[i++] = m_eos_char;
    msec_timeout = ([super getUsecTimeout] + 999) / 1000;
    retval = pthread_mutex_lock(&m_bulk_transfer_lock);
    if(retval)
    {
        //free(out_data);
        return retval;
    }
    retval = [self send_bulk_msg:out_data : i : &bytes_written : msec_timeout];
    //free(out_data);
    if(retval || bytes_written != i)
    {
        GPIB_DPRINTK("%s: send_bulk_msg returned %i, bytes_written=%i, i=%i\n", __FILE__, retval, bytes_written, i);
        pthread_mutex_unlock(&m_bulk_transfer_lock);
        if(retval < 0) return retval;
        return -EIO;
    }
    in_data_length = length + 1;
    //in_data = calloc(in_data_length, sizeof(UInt8));
    //retval = [self receive_bulk_msg:in_data : in_data_length :&bytes_read : msec_timeout];
    retval = [self receive_bulk_msg:buffer : in_data_length :&bytes_read : msec_timeout];
    if(retval == -ETIMEDOUT)
    {
        UInt32 extra_bytes_read;
        SInt32 extra_bytes_retval;
        [self abort:YES];
        //extra_bytes_retval = [self receive_bulk_msg:in_data + bytes_read : in_data_length - bytes_read : &extra_bytes_read : 100];
        extra_bytes_retval = [self receive_bulk_msg:buffer + bytes_read : in_data_length - bytes_read : &extra_bytes_read : 100];
        GPIB_DPRINTK("%s: %s: receive_bulk_msg timed out, bytes_read=%i, extra_bytes_read=%i\n",
              __FILE__, __FUNCTION__, bytes_read, extra_bytes_read);
        bytes_read += extra_bytes_read;
        if(extra_bytes_retval)
        {
            GPIB_DPRINTK("%s: %s: extra_bytes_retval=%i, bytes_read=%i\n", __FILE__, __FUNCTION__,
                  extra_bytes_retval, bytes_read);
            [self abort:NO];
        }
    }else if(retval)
    {
        GPIB_DPRINTK("%s: %s: receive_bulk_msg returned %i, bytes_read=%i\n", __FILE__, __FUNCTION__,
              retval, bytes_read);
        [self abort:NO];
    }
    pthread_mutex_unlock(&m_bulk_transfer_lock);
    if(bytes_read > length + 1)
    {
        bytes_read = length + 1;
        GPIB_DPRINTK("%s: %s: bytes_read > length? truncating", __FILE__, __FUNCTION__);
    }
    //GPIB_DPRINTK("%s: %s: received response:\n", __FILE__, __FUNCTION__);
    //dump_raw_block(in_data, in_data_length);
    if(bytes_read >= 1)
    {
        //memcpy(buffer, in_data, bytes_read - 1);
        //trailing_flags = in_data[bytes_read - 1];
        trailing_flags = buffer[bytes_read - 1];
        *nbytes_read = bytes_read - 1;
        if(trailing_flags & (ATRF_EOI | ATRF_EOS)) *end = YES;
    }
    //free(in_data);
    //FIXME check trailing flags for error
    return retval;
}

-(SInt32) generic_write:(UInt8 *) buffer : (UInt32) length : (BOOL) send_commands : (BOOL) send_eoi : (UInt32 *) bytes_written
{
    SInt32 retval;
    UInt8 status_data[0x8] = {0,0,0,0,0,0,0,0};
    UInt8 * out_data;
    SInt32 out_data_length;
    UInt32 raw_bytes_written;
    UInt32 i = 0, j;
    UInt32 msec_timeout;
    
    *bytes_written = 0;
    out_data_length = length + 0x8;
    out_data = calloc(out_data_length, sizeof(UInt8));
    out_data[i++] = DATA_PIPE_CMD_WRITE;
    out_data[i++] = 0; // primary address when AWF_NO_ADDRESS is not set
    out_data[i++] = 0; // secondary address when AWF_NO_ADDRESS is not set
    out_data[i] = AWF_NO_ADDRESS | AWF_NO_FAST_TALKER_FIRST_BYTE;
    if(send_commands)
        out_data[i] |= AWF_ATN | AWF_NO_FAST_TALKER;
    if(send_eoi)
        out_data[i] |= AWF_SEND_EOI;
    ++i;
    out_data[i++] = length & 0xff;
    out_data[i++] = (length >> 8) & 0xff;
    out_data[i++] = (length >> 16) & 0xff;
    out_data[i++] = (length >> 24) & 0xff;
    for(j = 0; j < length; j++)
        out_data[i++] = buffer[j] & 0xff;
    //GPIB_DPRINTK("%s: sending bulk msg(), send_commands=%i\n", __FUNCTION__, send_commands);
    [gpib_board clear_bit:AIF_WRITE_COMPLETE_BN : &m_private.interrupt_flags];
    msec_timeout = [super getUsecTimeout] / 1000;
    retval = pthread_mutex_lock(&m_bulk_transfer_lock);
    if(retval)
    {
        free(out_data);
        return retval;
    }
    retval = [self send_bulk_msg:out_data : i : &raw_bytes_written : msec_timeout];
    free(out_data);
    if(retval || raw_bytes_written != i)
    {
        [self abort:NO];
        GPIB_DPRINTK("%s: send_bulk_msg returned %i, raw_bytes_written=%i, i=%i\n", __FILE__, retval, raw_bytes_written, i);
        pthread_mutex_unlock(&m_bulk_transfer_lock);
        if(retval < 0) return retval;
        return -EIO;
    }
    CFRunLoopRunResult res = 0;
    while(res!=kCFRunLoopRunTimedOut) {
        res = CFRunLoopRunInMode(kCFRunLoopDefaultMode, (msec_timeout/1000.0), YES);
        if([gpib_board test_bit:AIF_WRITE_COMPLETE_BN : &m_private.interrupt_flags] || [gpib_board test_bit:TIMO_NUM : &m_private_board.status])
        {
            //GPIB_DPRINTK("Interrupt completed in generic Write");
            break;
        }
    }
    if(retval)
    {
        GPIB_DPRINTK("%s: %s: wait interrupted\n", __FILE__, __FUNCTION__);
        [self abort:NO];
        pthread_mutex_unlock(&m_bulk_transfer_lock);
        return -EIO;
    }
    if([gpib_board test_bit:AIF_WRITE_COMPLETE_BN : &m_private.interrupt_flags] == NO)
    {
        GPIB_DPRINTK("Abort generic Write %u", m_private.interrupt_flags);
        [self abort:NO];
    }
    //GPIB_DPRINTK("%s: receiving control msg\n", __FUNCTION__);
    retval = [self receive_control_msg:control_request : USB_DIR_IN | USB_TYPE_VENDOR | USB_RECIP_DEVICE : XFER_STATUS : 0 : status_data : sizeof(status_data) : 100];
    pthread_mutex_unlock(&m_bulk_transfer_lock);
    if(retval < 0)
    {
        GPIB_DPRINTK("%s: %s: receive_control_msg() returned %i\n", __FILE__, __FUNCTION__, retval);
        return -EIO;
    }
    *bytes_written = status_data[2];
    *bytes_written |= status_data[3] << 8;
    *bytes_written |= status_data[4] << 16;
    *bytes_written |= status_data[5] << 24;
    //GPIB_DPRINTK("%s: write completed, bytes_completed=%i\n", __FUNCTION__, bytes_completed);
    return 0;
}

-(SInt32) write:(UInt8 *) buffer : (UInt32) length : (BOOL) send_eoi : (UInt32 *) bytes_written
{
    return [self generic_write:buffer : length : NO : send_eoi : bytes_written];
}

-(SInt32) command:(UInt8 *)buffer : (UInt32) length : (UInt32 *) bytes_written
{
    return [self generic_write:buffer : length : YES : NO : bytes_written];
}

-(SInt32) take_control:(BOOL) synchronous
{
    struct register_pairlet write;
    SInt32 retval;
    
    write.address = AUXCR;
    if(synchronous==YES)
    {
        write.value = AUX_TCS;
    }else
        write.value = AUX_TCA;
    retval = [self write_registers:&write : 1];
    if(retval)
    {
        GPIB_DPRINTK("%s: %s: write_registers() returned error\n", __FILE__, __FUNCTION__);
    }
    
    return retval;
}

-(SInt32) go_to_standby
{
    struct register_pairlet write;
    SInt32 retval;
    
    write.address = AUXCR;
    write.value = AUX_GTS;
    retval = [self write_registers:&write : 1];
    if(retval)
    {
        GPIB_DPRINTK("%s: %s: write_registers() returned error\n", __FILE__, __FUNCTION__);
    }
    return retval;
}

-(SInt32) request_system_control:(BOOL) request_control
{
    struct register_pairlet writes[2];
    SInt32 retval;
    UInt32 i = 0;
    
    // 82357B needs bit to be set in 9914 AUXCR register
    writes[i].address = AUXCR;
    if(request_control)
    {
        writes[i].value = AUX_RQC;
        m_hw_control_bits |= SYSTEM_CONTROLLER;
    }else
    {
        writes[i].value = AUX_RLC;
        m_is_cic = NO;
        m_hw_control_bits &= ~SYSTEM_CONTROLLER;
    }
    ++i;
    writes[i].address = HW_CONTROL;
    writes[i].value = m_hw_control_bits;
    ++i;
    retval = [self write_registers:writes : i];
    if(retval)
    {
        GPIB_DPRINTK("%s: %s: write_registers() returned error\n", __FILE__, __FUNCTION__);
    }
    return retval;
}

-(SInt32) interface_clear:(BOOL) assert
{
    struct register_pairlet write;
    SInt32 retval;
    
    write.address = AUXCR;
    write.value = AUX_SIC;
    if(assert)
    {
        write.value |= AUX_CS;
        m_is_cic = YES;
    }
    retval = [self write_registers:&write : 1];
    if(retval)
    {
        GPIB_DPRINTK("%s: %s: write_registers() returned error\n", __FILE__, __FUNCTION__);
    }
    return retval;
}

-(SInt32) remote_enable:(BOOL) enable
{
    struct register_pairlet write;
    SInt32 retval;

    write.address = AUXCR;
    write.value = AUX_SRE;
    if(enable)
    {
        write.value |= AUX_CS;
    }
    retval = [self write_registers:&write : 1];
    if(retval)
    {
        GPIB_DPRINTK("%s: %s: write_registers() returned error\n", __FILE__, __FUNCTION__);
    }
    return retval;
}

-(SInt32) enable_eos:(UInt8) eos_byte : (BOOL) compare_8_bits
{
    if(compare_8_bits == NO)
    {
        GPIB_DPRINTK("%s: %s: hardware only supports 8-bit EOS compare", __FILE__, __FUNCTION__);
        return -EOPNOTSUPP;
    }
    m_eos_char = eos_byte;
    m_eos_mode = REOS | BIN;
    return 0;
}

-(void) disable_eos
{
    m_eos_mode &= ~REOS;
}

-(UInt32) update_status:(UInt32) clear_mask
{
    struct register_pairlet address_status;
    SInt32 retval;
    UInt32 status;
    
    m_private_board.status &= ~clear_mask;
    status = m_private_board.status;
    if(m_is_cic)
        status |= CIC;
    else
        status &= ~CIC;
    address_status.address = ADSR;
    retval = [self read_registers:&address_status : 1 : NO];
    if(retval)
    {
        GPIB_DPRINTK("%s: %s: read_registers() returned error\n", __FILE__, __FUNCTION__);
        return status;
    }
    // check for remote/local
    if(address_status.value & HR_REM)
        [gpib_board set_bit:REM_NUM : &status];
    else
        [gpib_board clear_bit:REM_NUM : &status];
    // check for lockout
    if(address_status.value & HR_LLO)
        [gpib_board set_bit:LOK_NUM : &status];
    else
        [gpib_board clear_bit:LOK_NUM : &status];
    // check for ATN
    if(address_status.value & HR_ATN)
        [gpib_board set_bit:ATN_NUM : &status];
    else
        [gpib_board clear_bit:ATN_NUM : &status];
    // check for talker/listener addressed
    if(address_status.value & HR_TA)
        [gpib_board set_bit:TACS_NUM : &status];
    else
        [gpib_board clear_bit:TACS_NUM : &status];
    if(address_status.value & HR_LA)
        [gpib_board set_bit:LACS_NUM : &status];
    else
        [gpib_board clear_bit:LACS_NUM : &status];
    return status;
}

-(SInt32) primary_address:(UInt16) address
{
    struct register_pairlet write;
    SInt32 retval;
    
    // put primary address in address0
    write.address = ADR;
    write.value = address & ADDRESS_MASK;
    retval = [self write_registers:&write : 1];
    if(retval)
    {
        GPIB_DPRINTK("%s: %s: write_registers() returned error\n", __FILE__, __FUNCTION__);
    }
    return retval;
}

-(void) secondary_address:(UInt16) address : (BOOL) enable
{
    if(enable==YES)
        GPIB_DPRINTK("%s: %s: warning: assigning a secondary address not supported\n", __FILE__, __FUNCTION__);
    return;
}

-(SInt32) parallel_poll:(UInt8 *) result
{
    struct register_pairlet writes[2];
    struct register_pairlet read;
    SInt32 retval;
    
    // execute parallel poll
    writes[0].address = AUXCR;
    writes[0].value = AUX_CS | AUX_RPP;
    writes[1].address = HW_CONTROL;
    writes[1].value = m_hw_control_bits & ~NOT_PARALLEL_POLL;
    retval = [self write_registers:writes : 2];
    if(retval)
    {
        GPIB_DPRINTK("%s: %s: write_registers() returned error\n", __FILE__, __FUNCTION__);
        return retval;
    }
    usleep(2);	//silly, since usb write will take way longer
    read.address = CPTR;
    retval = [self read_registers:&read : 1 : YES];
    if(retval)
    {
        GPIB_DPRINTK("%s: %s: read_registers() returned error\n", __FILE__, __FUNCTION__);
        return retval;
    }
    *result = read.value;
    // clear parallel poll state
    writes[0].address = HW_CONTROL;
    writes[0].value = m_hw_control_bits | NOT_PARALLEL_POLL;
    writes[1].address = AUXCR;
    writes[1].value = AUX_RPP;
    retval = [self write_registers:writes : 2];
    if(retval)
    {
        GPIB_DPRINTK("%s: %s: write_registers() returned error\n", __FILE__, __FUNCTION__);
        return retval;
    }
    return 0;
}
-(void) parallel_poll_configure:(UInt8) config
{
    //board can only be system controller
    return;// 0;
}
-(void) parallel_poll_response:(UInt32) ist
{
    //board can only be system controller
    return;// 0;
}
-(void) serial_poll_response:(UInt8) status
{
    //board can only be system controller
    return;// 0;
}
-(UInt8) serial_poll_status
{
    //board can only be system controller
    return 0;
}
-(void) return_to_local
{
    //board can only be system controller
    return;// 0;
}
-(SInt32) line_status
{
    struct register_pairlet bus_status;
    SInt32 retval;
    UInt32 status = ValidALL;
    
    bus_status.address = BSR;
    retval = [self read_registers:&bus_status : 1 : NO];
    if(retval)
    {
        GPIB_DPRINTK("%s: %s: read_registers() returned error\n", __FILE__, __FUNCTION__);
        return 0;
    }
    if( bus_status.value & BSR_REN_BIT )
        status |= BusREN;
    if( bus_status.value & BSR_IFC_BIT )
        status |= BusIFC;
    if( bus_status.value & BSR_SRQ_BIT )
        status |= BusSRQ;
    if( bus_status.value & BSR_EOI_BIT )
        status |= BusEOI;
    if( bus_status.value & BSR_NRFD_BIT )
        status |= BusNRFD;
    if( bus_status.value & BSR_NDAC_BIT )
        status |= BusNDAC;
    if( bus_status.value & BSR_DAV_BIT )
        status |= BusDAV;
    if( bus_status.value & BSR_ATN_BIT )
        status |= BusATN;
    return status;
}

-(UInt16) nanosec_to_fast_talker_bits:(UInt32 *) nanosec
{
    const UInt16 nanosec_per_bit = 21;
    const UInt16 max_value = 0x72;
    const UInt16 min_value = 0x11;
    UInt16 bits;
    
    bits = (*nanosec + nanosec_per_bit / 2) / nanosec_per_bit;
    if(bits < min_value) bits = min_value;
    if(bits > max_value) bits = max_value;
    *nanosec = bits * nanosec_per_bit;
    return bits;
}

-(UInt32) t1_delay:(UInt32) nanosec
{
    struct register_pairlet write;
    SInt32 retval;
    
    write.address = FAST_TALKER_T1;
    write.value = [self nanosec_to_fast_talker_bits:&nanosec];
    retval = [self write_registers:&write : 1];
    if(retval)
    {
        GPIB_DPRINTK("%s: %s: write_registers() returned error\n", __FILE__, __FUNCTION__);
    }
    return nanosec;
}


-(SInt32) setup_urbs
{
    UInt8 int_pipe;
    SInt32 retval;
    
    retval = pthread_mutex_lock(&m_interrupt_alloc_lock);
    if(retval) return retval;
    if(m_private.bus_interface == NULL)
    {
        pthread_mutex_unlock(&m_interrupt_alloc_lock);
        return -ENODEV;
    }
    
    int_pipe = m_private.interrupt_in_endpoint;
    retval = (*m_private.bus_interface)->ReadPipeAsync(m_private.bus_interface, int_pipe, m_private.interrupt_buffer, sizeof(m_private.interrupt_buffer), &interrupt_complete, &m_private);
    if(retval)
    {
        GPIB_DPRINTK("%s: failed to submit first interrupt urb, retval=%i\n", __FILE__, retval);
        pthread_mutex_unlock(&m_interrupt_alloc_lock);
        return retval;
    }
    pthread_mutex_unlock(&m_interrupt_alloc_lock);
    return 0;
}

-(SInt32) allocate_private
{
    if(m_private.maxInterruptPacketSize<=0)
        return -ENOMEM;
    pthread_mutex_init(&m_bulk_transfer_lock, NULL);
    pthread_mutex_init(&m_bulk_alloc_lock, NULL);
    pthread_mutex_init(&m_control_alloc_lock, NULL);
    pthread_mutex_init(&m_interrupt_alloc_lock, NULL);
    m_private.interrupt_buffer = calloc(m_private.maxInterruptPacketSize, sizeof(UInt32));
    m_private.board = &m_private_board;
    return 0;
}

-(SInt32) init_interface
{
    struct register_pairlet hw_control;
    struct register_pairlet writes[0x20];
    SInt32 retval;
    UInt32 i;
    UInt32 nanosec;
    
    i = 0;
    writes[i].address = LED_CONTROL;
    writes[i].value = FAIL_LED_ON;
    ++i;
    writes[i].address = RESET_TO_POWERUP;
    writes[i].value = RESET_SPACEBALL;
    ++i;
    retval = [self write_registers:writes : i];
    if(retval)
    {
        GPIB_DPRINTK("%s: %s: write_registers() returned error\n", __FILE__, __FUNCTION__);
        return -EIO;
    }
    usleep(2000);
    i = 0;
    writes[i].address = AUXCR;
    writes[i].value = AUX_NBAF;
    ++i;
    writes[i].address = AUXCR;
    writes[i].value = AUX_HLDE;
    ++i;
    writes[i].address = AUXCR;
    writes[i].value = AUX_TON;
    ++i;
    writes[i].address = AUXCR;
    writes[i].value = AUX_LON;
    ++i;
    writes[i].address = AUXCR;
    writes[i].value = AUX_RSV2;
    ++i;
    writes[i].address = AUXCR;
    writes[i].value = AUX_INVAL;
    ++i;
    writes[i].address = AUXCR;
    writes[i].value = AUX_RPP;
    ++i;
    writes[i].address = AUXCR;
    writes[i].value = AUX_STDL;
    ++i;
    writes[i].address = AUXCR;
    writes[i].value = AUX_VSTDL;
    ++i;
    writes[i].address = FAST_TALKER_T1;
    nanosec = 800;
    writes[i].value = [self nanosec_to_fast_talker_bits:&nanosec];
    [super setT1NanoNsec:nanosec];
    ++i;
    writes[i].address = ADR;
    writes[i].value = [super getPad] & ADDRESS_MASK;
    ++i;
    writes[i].address = PPR;
    writes[i].value = 0;
    ++i;
    writes[i].address = SPMR;
    writes[i].value = 0;
    ++i;
    writes[i].address = PROTOCOL_CONTROL;
    writes[i].value = WRITE_COMPLETE_INTERRUPT_EN;
    ++i;
    writes[i].address = IMR0;
    writes[i].value = HR_BOIE | HR_BIIE;
    ++i;
    writes[i].address = IMR1;
    writes[i].value = HR_SRQIE;
    ++i;
    // turn off reset state
    writes[i].address = AUXCR;
    writes[i].value = AUX_CHIP_RESET;
    ++i;
    writes[i].address = LED_CONTROL;
    writes[i].value = FIRMWARE_LED_CONTROL;
    ++i;
    if(i > sizeof(writes) / sizeof(writes[0]))
    {
        GPIB_DPRINTK("%s: %s: bug! writes[] overflow\n", __FILE__, __FUNCTION__);
        return -EFAULT;
    }
    retval = [self write_registers:writes : i];
    if(retval)
    {
        GPIB_DPRINTK("%s: %s: write_registers() returned error\n", __FILE__, __FUNCTION__);
        return -EIO;
    }
    hw_control.address = HW_CONTROL;
    retval = [self read_registers:&hw_control : 1 : YES];
    if(retval)
    {
        GPIB_DPRINTK("%s: %s: read_registers() returned error\n", __FILE__, __FUNCTION__);
        return -EIO;
    }
    m_hw_control_bits = (hw_control.value & ~0x7) | NOT_TI_RESET | NOT_PARALLEL_POLL;
    return 0;
}

-(NSString*) getUSBStringDescriptor:(IOUSBDeviceInterface300**) usbDevice :(UInt8) idx
{
    assert( usbDevice );
    char buffer[128], myBuffer[64];
    
    // wow... we're actually forced to make hard coded bus requests. Its like
    // hard disk programming in the 80's!
    IOUSBDevRequest request;
    
    request.bmRequestType = USBmakebmRequestType(
                                                 kUSBIn,
                                                 kUSBStandard,
                                                 kUSBDevice );
    request.bRequest = kUSBRqGetDescriptor;
    request.wValue = (kUSBStringDesc << 8) | idx;
    request.wIndex = 0x409; // english
    request.wLength = sizeof( buffer );
    request.pData = buffer;
    
    kern_return_t err = (*usbDevice)->DeviceRequest( usbDevice, &request );
    if ( err != 0 )
    {
        return @"None";
    }
    
    UInt32 count = ( request.wLenDone-1) / 2;
    for(UInt32 i=0; i<count; i++)
        myBuffer[i] = buffer[2*(i+1)];
    myBuffer[count] = '\0';
    //printf("read :%s\n", myBuffer);
    NSString *reply = [[NSString alloc] initWithUTF8String:myBuffer];
    return reply;
}

-(SInt32) attach
{
    SInt32 retval;
    m_private.bus_interface = nil;
    m_private.maxInOutPacketSize = 0x4000;
    part_type partType = ptUNDEF;
    io_service_t device;
    kern_return_t kr;
    CFMutableDictionaryRef matchingDict;
    io_iterator_t iter;
    HRESULT res;
    SInt32 score;
    UInt16 pid, vid;
    IOCFPlugInInterface **plugInInterface = NULL;
    IOUSBDeviceInterface300 **deviceInterface = NULL;
    BOOL bFound = NO;
    
    /* set up a matching dictionary for the class */
    matchingDict = IOServiceMatching(kIOUSBDeviceClassName);
    if (matchingDict == NULL)
    {
        return -EIO; // fail
    }
    
    /* Now we have a dictionary, get an iterator.*/
    kr = IOServiceGetMatchingServices(kIOMasterPortDefault, matchingDict, &iter);
    if (kr != KERN_SUCCESS)
    {
        return -EIO;
    }
    
    if(pthread_mutex_lock(&hotplug_lock))
        return -ERESTARTSYS;
    
    while ((device = IOIteratorNext(iter)) && bFound == NO) {
        
        kr = IOCreatePlugInInterfaceForService(device, kIOUSBDeviceUserClientTypeID, kIOCFPlugInInterfaceID, &plugInInterface, &score);
        assert(kr == kIOReturnSuccess);
        assert(plugInInterface);
        
        res = (*plugInInterface)->QueryInterface(plugInInterface, CFUUIDGetUUIDBytes(kIOUSBDeviceInterfaceID), (LPVOID*) &deviceInterface);
        
        (*plugInInterface)->Release(plugInInterface);
        assert(!res);
        assert(deviceInterface);
        
        kr = IOObjectRelease(device);
        assert(kr == kIOReturnSuccess);
        
        kr = (*deviceInterface)->GetDeviceVendor(deviceInterface, &vid);
        assert(kr == kIOReturnSuccess);
        kr = (*deviceInterface)->GetDeviceProduct(deviceInterface, &pid);
        assert(kr == kIOReturnSuccess);
        
        //fprintf(stderr, "vid = 0x%04x pid = 0x%04x\n", vid, pid);
        if(vid == USB_VENDOR_ID_AGILENT)
        {
            switch(pid)
            {
                case USB_DEVICE_ID_AGILENT_82357A_PREINIT:
                    partType = ptFX;
                    ezusb_load_ram((IOUSBDeviceInterface **)deviceInterface,@"82357a_fw.hex", partType, FALSE);
                    sleep(4);
                    (*deviceInterface)->ResetDevice(deviceInterface);
                    (*deviceInterface)->USBDeviceClose(deviceInterface);
                    (*deviceInterface)->Release(deviceInterface);
                    IOObjectRelease(iter);
                    matchingDict = IOServiceMatching(kIOUSBDeviceClassName);
                    if (matchingDict == NULL)
                    {
                        return -ENODEV;
                    }
                    kr = IOServiceGetMatchingServices(kIOMasterPortDefault, matchingDict, &iter);
                    if (kr != KERN_SUCCESS)
                    {
                        return -ENODEV;
                    }
                    break;
                case USB_DEVICE_ID_AGILENT_82357B_PREINIT:
                    partType = ptFX2;
                    ezusb_load_ram((IOUSBDeviceInterface **)deviceInterface, @"measat_releaseX1.8.hex", partType, FALSE);
                    sleep(4);
                    (*deviceInterface)->ResetDevice(deviceInterface);
                    (*deviceInterface)->USBDeviceClose(deviceInterface);
                    (*deviceInterface)->Release(deviceInterface);
                    IOObjectRelease(iter);
                    matchingDict = IOServiceMatching(kIOUSBDeviceClassName);
                    if (matchingDict == NULL)
                    {
                        return -ENODEV;
                    }
                    kr = IOServiceGetMatchingServices(kIOMasterPortDefault, matchingDict, &iter);
                    if (kr != KERN_SUCCESS)
                    {
                        return -ENODEV;
                    }
                    break;
                case USB_DEVICE_ID_AGILENT_82357A:
                case USB_DEVICE_ID_AGILENT_82357B:
                    (*deviceInterface)->ResetDevice(deviceInterface);
                    sleep(2);
                    if([self selectInterface: deviceInterface])
                    {
                        bFound = YES;
                        UInt8 devId, snId;
                        (*deviceInterface)->USBGetProductStringIndex(deviceInterface, &devId);
                        (*deviceInterface)->USBGetSerialNumberStringIndex(deviceInterface, &snId);
                        NSString *deviceName = [self getUSBStringDescriptor:deviceInterface :devId];
                        NSString *serialNumber = [self getUSBStringDescriptor:deviceInterface :snId];
                        NSMutableString *sqlStatement = [NSMutableString string];
                        [sqlStatement appendFormat:@"%s - S/N:%s", [deviceName UTF8String], [serialNumber UTF8String] ];
                        m_name = [[NSString alloc] initWithUTF8String:[sqlStatement UTF8String]];
                        (*deviceInterface)->Release(deviceInterface);
                    }
                    else
                    {
                        (*deviceInterface)->USBDeviceClose(deviceInterface);
                        (*deviceInterface)->Release(deviceInterface);
                    }
                    break;
                default:
                    (*deviceInterface)->USBDeviceClose(deviceInterface);
                    (*deviceInterface)->Release(deviceInterface);
                    break;
                    
            }
        }
        else
        {
            (*deviceInterface)->USBDeviceClose(deviceInterface);
            (*deviceInterface)->Release(deviceInterface);
        }
    }
    
    /* Done, release the iterator */
    IOObjectRelease(iter);
    if(bFound==NO)
    {
        pthread_mutex_unlock(&hotplug_lock);
        //printf("No Agilent 82357 gpib adapters found\n");
        return -ENODEV;
    }
    (*m_private.bus_interface)->CreateInterfaceAsyncEventSource(m_private.bus_interface, &m_compl_event_source);
    CFRunLoopAddSource(CFRunLoopGetCurrent(), m_compl_event_source, kCFRunLoopDefaultMode);
    (*m_private.bus_interface)->SetAlternateInterface(m_private.bus_interface, 0);
    
    retval = [self allocate_private];
    if(retval < 0)
    {
        pthread_mutex_unlock(&hotplug_lock);
        return retval;
    }

    [self gpib_allocate_board:m_private.maxInOutPacketSize];
    /* Force resync with host and devie */
    (*m_private.bus_interface)->ClearPipeStallBothEnds(m_private.bus_interface,m_private.bulk_out_endpoint);
    (*m_private.bus_interface)->ClearPipeStallBothEnds(m_private.bus_interface,m_private.bulk_in_endpoint);
    (*m_private.bus_interface)->ClearPipeStallBothEnds(m_private.bus_interface,m_private.interrupt_in_endpoint);
    
    retval = [self setup_urbs];
    if(retval < 0)
    {
        GPIB_DPRINTK("Failed to setup urbs");
        pthread_mutex_unlock(&hotplug_lock);
        return retval;
    }
    //GPIB_DPRINTK("%s: finished setup_urbs()()\n", __FUNCTION__);
    retval = [self init_interface];
    if(retval < 0)
    {
        pthread_mutex_unlock(&hotplug_lock);
        return retval;
    }
    //GPIB_DPRINTK("%s: finished init()\n", __FUNCTION__);
    GPIB_DPRINTK("%s: attached\n", __FUNCTION__);
    pthread_mutex_unlock(&hotplug_lock);
    return retval;
}

-(SInt32) go_idle
{
    struct register_pairlet writes[0x20];
    SInt32 retval;
    UInt32 i;
    
    i = 0;
    // turn on tms9914 reset state
    writes[i].address = AUXCR;
    writes[i].value = AUX_CS | AUX_CHIP_RESET;
    ++i;
    m_hw_control_bits &= ~NOT_TI_RESET;
    writes[i].address = HW_CONTROL;
    writes[i].value = m_hw_control_bits;
    ++i;
    writes[i].address = PROTOCOL_CONTROL;
    writes[i].value = 0;
    ++i;
    writes[i].address = IMR0;
    writes[i].value = 0;
    ++i;
    writes[i].address = IMR1;
    writes[i].value = 0;
    ++i;
    writes[i].address = LED_CONTROL;
    writes[i].value = 0;
    ++i;
    if(i > sizeof(writes) / sizeof(writes[0]))
    {
        GPIB_DPRINTK("%s: %s: bug! writes[] overflow\n", __FILE__, __FUNCTION__);
        return -EFAULT;
    }
    retval = [self write_registers:writes : i];
    if(retval)
    {
        GPIB_DPRINTK("%s: %s: write_registers() returned error\n", __FILE__, __FUNCTION__);
        return -EIO;
    }
    return 0;
}

-(void) detach
{
    pthread_mutex_unlock(&hotplug_lock);
    if(m_private.bus_interface)
    {
        [self go_to_standby];
        (*m_private.bus_interface)->ClearPipeStallBothEnds(m_private.bus_interface,m_private.bulk_out_endpoint);
        (*m_private.bus_interface)->ClearPipeStallBothEnds(m_private.bus_interface,m_private.bulk_in_endpoint);
        (*m_private.bus_interface)->ClearPipeStallBothEnds(m_private.bus_interface,m_private.interrupt_in_endpoint);
    }

    if(m_private.interrupt_buffer!=nil)
        free(m_private.interrupt_buffer);
    if(m_compl_event_source!=nil)
    {
        CFRunLoopRemoveSource(CFRunLoopGetCurrent(), m_compl_event_source, kCFRunLoopDefaultMode);
        CFRelease(m_compl_event_source);
        m_compl_event_source = nil;
    }
    if( m_private.bus_interface )
    {
        (*m_private.bus_interface)->USBInterfaceClose(m_private.bus_interface);
        (*m_private.bus_interface)->Release(m_private.bus_interface);
        m_private.bus_interface = nil;
        GPIB_DPRINTK("Interface Released");
    }
    GPIB_DPRINTK("%s: detached\n", __FUNCTION__);
    
    pthread_mutex_unlock(&hotplug_lock);
    [self gpib_deallocate_board];
    CFRunLoopStop(CFRunLoopGetCurrent());
}

-(BOOL) selectInterface:(IOUSBDeviceInterface300**) device
{
    IOReturn                    kr;
    IOUSBFindInterfaceRequest   request;
    io_iterator_t               iterator;
    io_service_t                usbInterface;
    IOCFPlugInInterface         **plugInInterface = nil;
    HRESULT                     result;
    SInt32                      score;
    UInt8                       interfaceClass;
    UInt8                       interfaceSubClass;
    UInt8                       interfaceNumEndpoints;
    SInt32                         pipeRef;
    m_private.bus_interface = nil;
    
    //Placing the constant kIOUSBFindInterfaceDontCare into the following
    //fields of the IOUSBFindInterfaceRequest structure will allow you
    //to find all the interface
    request.bInterfaceClass = kIOUSBFindInterfaceDontCare;
    request.bInterfaceSubClass = kIOUSBFindInterfaceDontCare;
    request.bInterfaceProtocol = kIOUSBFindInterfaceDontCare;
    request.bAlternateSetting = kIOUSBFindInterfaceDontCare;
    //Get an iterator for the interfaces on the device
    (*device)->CreateInterfaceIterator(device, &request, &iterator);
    while ((usbInterface = IOIteratorNext(iterator)))
    {
        //Create an intermediate plug-in
        kr = IOCreatePlugInInterfaceForService(usbInterface,
                                               kIOUSBInterfaceUserClientTypeID,
                                               kIOCFPlugInInterfaceID,
                                               &plugInInterface, &score);
        //Release the usbInterface object after getting the plug-in
        IOObjectRelease(usbInterface);
        if ((kr != kIOReturnSuccess) || !plugInInterface)
        {
            GPIB_DPRINTK("Unable to create a plug-in (%08x)\n", kr);
            break;
        }
        //Now create the device interface for the interface
        result = (*plugInInterface)->QueryInterface(plugInInterface,
                                                    CFUUIDGetUUIDBytes(kIOUSBInterfaceInterfaceID),
                                                    (LPVOID *) &m_private.bus_interface);
        //No longer need the intermediate plug-in
        (*plugInInterface)->Release(plugInInterface);
        if (result || !m_private.bus_interface)
        {
            GPIB_DPRINTK("Couldn’t create a device interface for the interface (%08x)\n", result);
            break;
        }
        //Get interface class and subclass
        (*m_private.bus_interface)->GetInterfaceClass(m_private.bus_interface,&interfaceClass);
        (*m_private.bus_interface)->GetInterfaceSubClass(m_private.bus_interface, &interfaceSubClass);
        //GPIB_DPRINTK("Interface class %d, subclass %d\n", interfaceClass, interfaceSubClass);
        //Now open the interface. This will cause the pipes associated with
        //the endpoints in the interface descriptor to be instantiated
        kr = (*m_private.bus_interface)->USBInterfaceOpen(m_private.bus_interface);
        if (kr != kIOReturnSuccess)
        {
            GPIB_DPRINTK("Unable to open interface (%08x)\n", kr);
            (void) (*m_private.bus_interface)->Release(m_private.bus_interface);
            m_private.bus_interface = nil;
            break;
        }
        
        //Get the number of endpoints associated with this interface
        kr = (*m_private.bus_interface)->GetNumEndpoints(m_private.bus_interface, &interfaceNumEndpoints);
        if (kr != kIOReturnSuccess)
        {
            GPIB_DPRINTK("Unable to get number of endpoints (%08x)\n", kr);
            (void) (*m_private.bus_interface)->USBInterfaceClose(m_private.bus_interface);
            (void) (*m_private.bus_interface)->Release(m_private.bus_interface);
            m_private.bus_interface = nil;
            break;
        }
        
        //GPIB_DPRINTK("Interface has %d endpoints\n", interfaceNumEndpoints);
        //Access each pipe in turn, starting with the pipe at index 1
        //The pipe at index 0 is the default control pipe and should be
        //accessed using (*usbDevice)->DeviceRequest() instead
        for (pipeRef = 1; pipeRef <= interfaceNumEndpoints; pipeRef++)
        {
            IOReturn        kr2;
            UInt8           direction;
            UInt8           number;
            UInt8           transferType;
            UInt16          maxPacketSize;
            UInt8           interval;
            
            kr2 = (*m_private.bus_interface)->GetPipeProperties(m_private.bus_interface,
                                                  pipeRef, &direction,
                                                  &number, &transferType,
                                                  &maxPacketSize, &interval);
            if (kr2 != kIOReturnSuccess)
                printf("Unable to get properties of pipe %d (%08x)\n",
                      pipeRef, kr2);
            else
            {
                if(direction == kUSBOut && transferType == kUSBBulk)
                {
                    m_private.bulk_out_endpoint = pipeRef;
                    GPIB_DPRINTK("Out Endpoint is %d", m_private.bulk_out_endpoint);
                    if(maxPacketSize < m_private.maxInOutPacketSize)
                        m_private.maxInOutPacketSize = maxPacketSize-8;
                }
                else if (direction == kUSBIn && transferType == kUSBBulk)
                {
                    m_private.bulk_in_endpoint = pipeRef;
                    GPIB_DPRINTK("In Endpoint is %d", m_private.bulk_in_endpoint);
                    if(maxPacketSize < m_private.maxInOutPacketSize)
                        m_private.maxInOutPacketSize = maxPacketSize-8;
                }
                else if (direction == kUSBIn && transferType == kUSBInterrupt)
                {
                    m_private.interrupt_in_endpoint = pipeRef;
                    GPIB_DPRINTK("Interrupt Endpoint is %d", m_private.interrupt_in_endpoint);
                    m_private.maxInterruptPacketSize = maxPacketSize;
                }
            }
        }
    }
    if(m_private.bus_interface != nil)
        return YES;
    else
        return NO;
}

@end
