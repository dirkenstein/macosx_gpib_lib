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

//#import <Foundation/Foundation.h>
#import "gpib_link.h"

/*static void DoNothingRunLoopCallback(void *info)
{
}*/

@implementation gpib_link

-(id) init_gpib_link:(Class) class_gpib_board
{
    self = [super init];
    m_port = [[NSPort alloc] init];
    m_linkthread = [[NSThread alloc] initWithTarget:self selector:@selector(linkThread) object:nil];
    [m_linkthread start];
    while([m_linkthread isExecuting]==NO);
    [self performSelector:@selector(init_gpib_sys:) onThread:m_linkthread withObject:class_gpib_board waitUntilDone:YES];
    m_class_gpib_board = class_gpib_board;
    return self;
}

-(void) cancelThread:(NSThread*) thread
{
    [self iboffline];
    [thread cancel];
    //CFRunLoopRef current = CFRunLoopGetCurrent();
    //CFRunLoopStop(current);
}

-(void) linkThread
{
    @autoreleasepool {
        NSRunLoop *runLoop = [NSRunLoop currentRunLoop];
        
        while ([[NSThread currentThread] isCancelled]==NO)
        {
            [runLoop runMode:NSDefaultRunLoopMode beforeDate:[NSDate distantFuture]];
            /*CFRunLoopSourceContext context = {0};
            context.perform = DoNothingRunLoopCallback;
            
            CFRunLoopSourceRef source = CFRunLoopSourceCreate(NULL, 0, &context);
            CFRunLoopAddSource(CFRunLoopGetCurrent(), source, kCFRunLoopCommonModes);
            
            // Keep processing events until the runloop is stopped.
            CFRunLoopRun();
            
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, kCFRunLoopCommonModes);
            CFRelease(source);*/
        }
    }
    [NSThread exit];
}

-(int) ioctl:(gpib_link_arg *)arg
{
    if(m_linkthread != nil)
    {
        if([m_linkthread isExecuting]==NO)
            return -1;
    }
    else
        return -1;
    pthread_mutex_lock(&m_board->m_big_gpib_mutex);
    //pthread_mutex_lock(&arg->lock);
    [self performSelector:@selector(ibioctl:) onThread:m_linkthread withObject:arg waitUntilDone:YES];
    //pthread_mutex_unlock(&arg->lock);
    pthread_mutex_unlock(&m_board->m_big_gpib_mutex);
    return arg->retval;
}

-(void) ibioctl:(gpib_link_arg *)arg
{
    //pthread_mutex_lock(&m_board->m_big_gpib_mutex);
    arg->retval = -ENOTTY;

    switch( arg->cmd )
    {
        case IBONL:
            arg->retval = [self online_ioctl:arg->bOnline];
            //pthread_mutex_unlock(&m_board->m_big_gpib_mutex);
            return;
            break;
        case IBAUTOSPOLL:
            arg->retval = [self autospoll_ioctl:arg->bAutospoll];
            //pthread_mutex_unlock(&m_board->m_big_gpib_mutex);
            return;
            break;
        case IBBOARD_INFO:
            arg->retval = [self board_info_ioctl:&arg->boardInfo];
            //pthread_mutex_unlock(&m_board->m_big_gpib_mutex);
            return;
            break;
        case IBMUTEX:
            // Need to unlock board->big_gpib_mutex before potentially locking board->user_mutex
            // to maintain consistent locking order
            //pthread_mutex_unlock(&m_board->m_big_gpib_mutex);
            arg->retval =  [self mutex_ioctl:arg->bMutex];
            return;
            break;
        case IBPAD:
            arg->retval = [self pad_ioctl:arg->handle : arg->pad];
            //pthread_mutex_unlock(&m_board->m_big_gpib_mutex);
            return;
            break;
        case IBSAD:
            arg->retval = [self sad_ioctl:arg->handle : arg->sad];
            //pthread_mutex_unlock(&m_board->m_big_gpib_mutex);
            return;
            break;
        default:
            break;
    }
    
    if( [m_board isOnline] == NO )
    {
        printf( "gpib: ioctl %i invalid for offline board\n",
               arg->cmd & 0xff );
        arg->retval = -EINVAL;
        //pthread_mutex_unlock(&m_board->m_big_gpib_mutex);
    }
    
    switch( arg->cmd )
    {
        case IBCLOSEDEV:
            arg->retval = [self close_dev_ioctl:arg->handle];
            //pthread_mutex_unlock(&m_board->m_big_gpib_mutex);
            return;
            break;
        case IBOPENDEV:
            arg->retval = [self open_dev_ioctl:&arg->handle : arg->pad : arg->sad : arg->bIsBoard];
            //pthread_mutex_unlock(&m_board->m_big_gpib_mutex);
            return;
            break;
        case IBSPOLL_BYTES:
            arg->retval = [self status_bytes_ioctl:&arg->nNumBytes : arg->pad : arg->sad];
            //pthread_mutex_unlock(&m_board->m_big_gpib_mutex);
            return;
            break;
        case IBWAIT:
            //arg->retval = [self wait_ioctl:&arg->wait];
            arg->retval = [self wait_ioctl:arg->read_ioctl];
            //pthread_mutex_unlock(&m_board->m_big_gpib_mutex);
            return;
            break;
        case IBLINES:
            arg->retval = [self line_status_ioctl:&arg->nLines];
            //pthread_mutex_unlock(&m_board->m_big_gpib_mutex);
            return;
            break;
        case IBLOC:
            [m_board return_to_local];
            arg->retval = 0;
            //pthread_mutex_unlock(&m_board->m_big_gpib_mutex);
            return;
            break;
        case IB_T1_DELAY:
            arg->retval = [self t1_delay_ioctl:arg->nDelay];
            //pthread_mutex_unlock(&m_board->m_big_gpib_mutex);
            return;
            break;
        case IBCAC:
            arg->retval = [self take_control_ioctl:arg->bTakeControl];
            //pthread_mutex_unlock(&m_board->m_big_gpib_mutex);
            return;
            break;
        case IBCMD:
            // IO ioctls can take a long time, we need to unlock board->big_gpib_mutex
            // before we call them.
            //pthread_mutex_unlock(&m_board->m_big_gpib_mutex);
            //arg->retval =  [self command_ioctl:&arg->readWrite];
            arg->retval =  [self command_ioctl:arg->read_ioctl];
            return;
            break;
        case IBEOS:
            arg->retval = [self eos_ioctl:arg->nEos :arg->nEosFlags];
            //pthread_mutex_unlock(&m_board->m_big_gpib_mutex);
            return;
            break;
        case IBGTS:
            arg->retval = [m_board go_to_standby];
            //pthread_mutex_unlock(&m_board->m_big_gpib_mutex);
            return;
            break;
        case IBPPC:
            arg->retval = [self ppc_ioctl:arg->nConfig : arg->bSetIst : arg->bClearIst];
            //pthread_mutex_unlock(&m_board->m_big_gpib_mutex);
            return;
            break;
        case IBQUERY_BOARD_RSV:
            arg->retval = [self query_board_rsv_ioctl:&arg->nStatus];
            //pthread_mutex_unlock(&m_board->m_big_gpib_mutex);
            return;
            break;
        case IBRD:
            // IO ioctls can take a long time, we need to unlock board->big_gpib_mutex
            // before we call them.
            //pthread_mutex_unlock(&m_board->m_big_gpib_mutex);
            //arg->retval =  [self read_ioctl:&arg->readWrite];
            arg->retval =  [self read_ioctl:arg->read_ioctl];
            return;
            break;
        case IBRPP:
            arg->retval = [self parallel_poll_ioctl:&arg->nPollByte];
            //pthread_mutex_unlock(&m_board->m_big_gpib_mutex);
            return;
            break;
        case IBRSC:
            arg->retval = [self request_system_control_ioctl:arg->bRequestControl];
            //pthread_mutex_unlock(&m_board->m_big_gpib_mutex);
            return;
            break;
        case IBRSP:
            arg->retval = [self serial_poll_ioctl:arg->pad : arg->sad : arg->nUsecDuration : &arg->nStatusByte];
            //pthread_mutex_unlock(&m_board->m_big_gpib_mutex);
            return;
            break;
        case IBRSV:
            arg->retval = [self request_service_ioctl:arg->nStatusByte];
            //pthread_mutex_unlock(&m_board->m_big_gpib_mutex);
            return;
            break;
        case IBSIC:
            arg->retval = [self interface_clear_ioctl:arg->nUsecDuration];
            //pthread_mutex_unlock(&m_board->m_big_gpib_mutex);
            break;
        case IBSRE:
            arg->retval = [self remote_enable_ioctl:arg->bEnable];
            //pthread_mutex_unlock(&m_board->m_big_gpib_mutex);
            return;
            break;
        case IBTMO:
            arg->retval = [self timeout_ioctl:arg->nUsecDuration];
            //pthread_mutex_unlock(&m_board->m_big_gpib_mutex);
            return;
            break;
        case IBWRT:
            // IO ioctls can take a long time, we need to unlock board->big_gpib_mutex
            // before we call them.
            //pthread_mutex_unlock(&m_board->m_big_gpib_mutex);
            //arg->retval = [self write_ioctl:&arg->readWrite];
            arg->retval = [self write_ioctl:arg->read_ioctl];
            return;
            break;
        default:
            arg->retval = -ENOTTY;
            //pthread_mutex_unlock(&m_board->m_big_gpib_mutex);
            return;
            break;
    }
}

-(int) ibopen
{
    if(m_linkthread != nil)
    {
        if([m_linkthread isExecuting]==YES)
        {
            pthread_mutex_lock(&m_board->m_big_gpib_mutex);
            [self performSelector:@selector(ibonline) onThread:m_linkthread withObject:nil waitUntilDone:YES];
            pthread_mutex_unlock(&m_board->m_big_gpib_mutex);
        }
    }
    else
        return -1;
    
    return 0;
}

-(int) ibclose
{
    if(m_linkthread != nil)
    {
        if([m_linkthread isExecuting]==YES)
        {
            pthread_mutex_lock(&m_board->m_big_gpib_mutex);
            [self performSelector:@selector(iboffline) onThread:m_linkthread withObject:nil waitUntilDone:YES];
            pthread_mutex_unlock(&m_board->m_big_gpib_mutex);
        }
    }
    else
        return -1;
    
    return 0;
}

-(int) close
{
    if(m_linkthread != nil)
        if([m_linkthread isExecuting])
        {
            pthread_mutex_lock(&m_board->m_big_gpib_mutex);
            [self performSelector:@selector(cancelThread:) onThread:m_linkthread withObject:m_linkthread waitUntilDone:YES];
            pthread_mutex_unlock(&m_board->m_big_gpib_mutex);
            while([m_linkthread isFinished]==NO);
        }
    [self cleanup_open_devices ];
    if(atomic_flag_test_and_set(&m_holding_mutex))
    {
        pthread_mutex_unlock(&m_user_mutex);
    }
    else
    {
        atomic_flag_clear(&m_holding_mutex);
    }
    return 0;
}

-(NSString*) ibname
{
    gpib_link_arg *arg = [[gpib_link_arg alloc]init];
    if([m_linkthread isExecuting])
    {
        pthread_mutex_lock(&m_board->m_big_gpib_mutex);
        [self performSelector:@selector(getBoardName:) onThread:m_linkthread withObject:arg waitUntilDone:YES];
        pthread_mutex_unlock(&m_board->m_big_gpib_mutex);
    }
    return arg->name;
}

//-(int) read_ioctl:(read_write_ioctl_t*) read_cmd
-(int) read_ioctl:(NSMutableDictionary*) read_cmd
{
    UInt16 remain;
    BOOL end_flag = NO;
    int read_ret = 0;
    gpib_descriptor *desc;
    UInt32 nbytes, index;
    
    //if(read_cmd->completed_transfer_count > read_cmd->requested_transfer_count)
    if( [[read_cmd valueForKey:@"completed_transfer_count"] intValue] >
        [[read_cmd valueForKey:@"requested_transfer_count"] intValue] )
        return -EINVAL;
    
    //desc = [self handle_to_descriptor:read_cmd->handle];
    desc = [self handle_to_descriptor:[[read_cmd valueForKey:@"handle"] intValue]];
    if( desc == NULL )
        return -EINVAL;
    
    //remain = read_cmd->requested_transfer_count - read_cmd->completed_transfer_count;
    remain = [[read_cmd valueForKey:@"requested_transfer_count"] intValue] -
                [[read_cmd valueForKey:@"completed_transfer_count"] intValue];
    
    atomic_flag_test_and_set(&desc->io_in_progress);
    /* Read buffer loads till we fill the user supplied buffer */
    index = 0;
    while(remain > 0 && end_flag == 0)
    {
        nbytes = 0;
        read_ret = [self ibrd:[m_board getBuffer] : (([m_board getBufferLength] < remain) ? [m_board getBufferLength] :
                                                        remain) : &end_flag : &nbytes];
        if(nbytes == 0) break;
        //for(int i = 0; i < nbytes ; i++)
            //read_cmd->buffer_ptr[i+index] = [m_board getBuffer][i];
        [[read_cmd valueForKey:@"buffer"] appendBytes:[m_board getBuffer] length:nbytes];
        index += nbytes;
        remain -= nbytes;
        if(read_ret < 0) break;
    }
    //read_cmd->completed_transfer_count = read_cmd->requested_transfer_count - remain;
    [read_cmd setValue:[NSNumber numberWithInt:[[read_cmd valueForKey:@"requested_transfer_count"] intValue] - remain] forKey:@"completed_transfer_count"];
    //read_cmd->end = end_flag;
    [read_cmd setValue:[NSNumber numberWithBool:end_flag] forKey:@"end"];
    /* suppress errors (for example due to timeout or interruption by device clear)
     if all bytes got sent.  This prevents races that can occur in the various drivers
     if a device receives a device clear immediately after a transfer completes and
     the driver code wasn't careful enough to handle that case.
     */
    if(remain == 0 || end_flag)
    {
        read_ret = 0;
    }
    atomic_flag_clear(&desc->io_in_progress);
    CFRunLoopSourceSignal(m_board->m_private_board.wait);
    CFRunLoopWakeUp(m_board->m_private_board.runner);
    return read_ret;
}

//-(SInt32) command_ioctl:(read_write_ioctl_t *) cmd
-(SInt32) command_ioctl:(NSMutableDictionary *) cmd
{
    SInt32 remain;
    SInt32 retval;
    gpib_descriptor *desc;
    UInt32 bytes_written = 0, index = 0, nbytes = 0;
    
    //if(cmd->completed_transfer_count > cmd->requested_transfer_count)
    if( [[cmd valueForKey:@"completed_transfer_count"] intValue] >
        [[cmd valueForKey:@"requested_transfer_count"] intValue] )
        return -EINVAL;
    
    //desc = [self handle_to_descriptor:cmd->handle];
    desc = [self handle_to_descriptor:[[cmd valueForKey:@"handle"] intValue]];
    if( desc == NULL ) return -EINVAL;
    
    //remain = cmd->requested_transfer_count - cmd->completed_transfer_count;
    remain = [[cmd valueForKey:@"requested_transfer_count"] intValue] -
                [[cmd valueForKey:@"completed_transfer_count"] intValue];
    
    /* Write buffer loads till we empty the user supplied buffer.
     Call drivers at least once, even if remain is zero, in
     order to allow them to insure previous commands were
     completely finished, in the case of a restarted ioctl.  */
    atomic_flag_test_and_set(&desc->io_in_progress);
    do
    {
        nbytes =(([m_board getBufferLength] < remain) ? [m_board getBufferLength]: remain);
        //for(int i = 0; i < (([m_board getBufferLength] < remain) ? [m_board getBufferLength]: remain) ; i++)
        //    [m_board getBuffer][i] = cmd->buffer_ptr[i+index];
        [[cmd valueForKey:@"buffer"] getBytes:[m_board getBuffer] range:NSMakeRange(index, nbytes)];
        //retval = [self ibcmd:[m_board getBuffer] : (([m_board getBufferLength] < remain) ?
        //                                               [m_board getBufferLength] : remain) : &bytes_written];
        retval = [self ibcmd:[m_board getBuffer] : nbytes : &bytes_written];
        index += bytes_written;
        remain -= bytes_written;
        if(retval < 0 || bytes_written == 0)
        {
            atomic_flag_clear(&desc->io_in_progress);
            CFRunLoopSourceSignal(m_board->m_private_board.wait);
            CFRunLoopWakeUp(m_board->m_private_board.runner);
            break;
        }
    }while( remain > 0 );
    
    //cmd->completed_transfer_count = cmd->requested_transfer_count - remain;
    [cmd setValue:[NSNumber numberWithInt:[[cmd valueForKey:@"requested_transfer_count"] intValue] - remain] forKey:@"completed_transfer_count"];
    
    atomic_flag_clear(&desc->io_in_progress);
    CFRunLoopSourceSignal(m_board->m_private_board.wait);
    CFRunLoopWakeUp(m_board->m_private_board.runner);
    
    return retval;
}

//-(SInt32) write_ioctl:(read_write_ioctl_t *) write_cmd
-(SInt32) write_ioctl:(NSMutableDictionary *) write_cmd
{
    SInt32 remain;
    SInt32 retval = 0;
    gpib_descriptor *desc;
    BOOL send_eoi;
    UInt32 bytes_written = 0, index =0, nbytes=0;
    
    //if(write_cmd->completed_transfer_count > write_cmd->requested_transfer_count)
    if( [[write_cmd valueForKey:@"completed_transfer_count"] intValue] >
       [[write_cmd valueForKey:@"requested_transfer_count"] intValue] )
        return -EINVAL;
    
    //desc = [self handle_to_descriptor:write_cmd->handle];
    desc = [self handle_to_descriptor:[[write_cmd valueForKey:@"handle"] intValue]];
    if( desc == NULL ) return -EINVAL;
    
    //remain = write_cmd->requested_transfer_count - write_cmd->completed_transfer_count;
    remain = [[write_cmd valueForKey:@"requested_transfer_count"] intValue] -
                [[write_cmd valueForKey:@"completed_transfer_count"] intValue];
    
    atomic_flag_test_and_set(&desc->io_in_progress);
    /* Write buffer loads till we empty the user supplied buffer */
    while(remain > 0)
    {
        nbytes =(([m_board getBufferLength] < remain) ? [m_board getBufferLength]: remain);
        //if(remain <= [m_board getBufferLength] && write_cmd->end)
        if(remain <= [m_board getBufferLength] && [[write_cmd valueForKey:@"send_eoi"] boolValue])
            send_eoi = YES;
        else
            send_eoi = NO;
        
        //for(int i = 0; i < (([m_board getBufferLength] < remain) ? [m_board getBufferLength] : remain) ; i++)
        //    [m_board getBuffer][i] = write_cmd->buffer_ptr[i+index];
        [[write_cmd valueForKey:@"buffer"] getBytes:[m_board getBuffer] range:NSMakeRange(index, nbytes)];
        
        //retval = [self ibwrt:[m_board getBuffer] : (([m_board getBufferLength]< remain) ?
        //                                               [m_board getBufferLength]: remain) : send_eoi : &bytes_written];
        retval = [self ibwrt:[m_board getBuffer] : nbytes : send_eoi : &bytes_written];
        
        index += bytes_written;
        remain -= bytes_written;
        if(retval < 0 || bytes_written == 0)
            break;
    }
    //write_cmd->completed_transfer_count = write_cmd->requested_transfer_count - remain;
    [write_cmd setValue:[NSNumber numberWithInt:[[write_cmd valueForKey:@"requested_transfer_count"] intValue] - remain] forKey:@"completed_transfer_count"];
    /* suppress errors (for example due to timeout or interruption by device clear)
     if all bytes got sent.  This prevents races that can occur in the various drivers
     if a device receives a device clear immediately after a transfer completes and
     the driver code wasn't careful enough to handle that case.
     */
    if(remain == 0)
        retval = 0;
    atomic_flag_clear(&desc->io_in_progress);
    CFRunLoopSourceSignal(m_board->m_private_board.wait);
    CFRunLoopWakeUp(m_board->m_private_board.runner);
    return retval;
}

-(int) open_dev_ioctl:(int *) handle : (unsigned int) pad : (int) sad : (BOOL) is_board
{
    int retval;
    gpib_descriptor * desc = NULL;
    
    if(pthread_mutex_lock(&m_descriptors_mutex))
    {
        return -ERESTARTSYS;
    }

    BOOL deviceExist = NO;
    /* first see if address has already been opened, then increment
     * open count */
    for(int index = 0; index < [m_descriptors count]; index ++)
    {
        desc = (gpib_descriptor*)[m_descriptors objectAtIndex:index];
        if( gpib_address_equal( desc->pad, desc->sad, pad, sad ) )
        {
            GPIB_DPRINTK( "Device pad %i, sad %i is already opened\n",
                         desc->pad, desc->sad );
            deviceExist = YES;
            *handle = index;
            pthread_mutex_unlock(&m_descriptors_mutex);
            break;
        }
    }
    if(!deviceExist)
    {
        desc = [[gpib_descriptor alloc] init];
        [self init_gpib_descriptor: desc];
        desc->pad = pad;
        desc->sad = sad;
        desc->is_board = is_board;
        [m_descriptors addObject:desc];
        pthread_mutex_unlock(&m_descriptors_mutex);
        *handle = (unsigned int)[m_descriptors count] - 1;
        retval = [m_board increment_open_device_count:pad : sad];
        if( retval < 0 )
            return retval;
    }
    return 0;
}

-(int) close_dev_ioctl:(unsigned int) handle
{
    int retval;
    gpib_descriptor* desc = nil;
    desc = [m_descriptors objectAtIndex:handle];
    if( desc == nil) return -EINVAL;
    
    retval = [m_board decrement_open_device_count:desc->pad : desc->sad];
    if( retval < 0 ) return retval;
    [m_descriptors removeObjectAtIndex:handle];
    //[desc release];
    
    return 0;
}

-(int) serial_poll_ioctl:(unsigned int) pad : (int) sad : (unsigned int) usec_timeout : (uint8_t *) status_byte
{
    int retval;
    
    GPIB_DPRINTK( "entering serial_poll_ioctl()\n" );
    
    retval = [self get_serial_poll_byte:pad : sad : usec_timeout : status_byte];
    if( retval < 0 )
        return retval;
    return 0;
}

//-(int) wait_ioctl:(wait_ioctl_t*) wait_cmd
-(int) wait_ioctl:(NSDictionary*) wait_cmd
{
    int retval;
    gpib_descriptor *desc;
    SInt32 ibsta = [[wait_cmd valueForKey:@"ibsta"] intValue];
    
    //desc = [self handle_to_descriptor:wait_cmd->handle];
    desc = [self handle_to_descriptor:[[wait_cmd valueForKey:@"handle"] intValue] ];
    if( desc == NULL ) return -EINVAL;
    
    //retval = [self ibwait:wait_cmd->wait_mask : wait_cmd->clear_mask :
    //          wait_cmd->set_mask : &wait_cmd->ibsta : wait_cmd->usec_timeout : desc];
    retval = [self ibwait:[[wait_cmd valueForKey:@"wait_mask"] intValue] :
                [[wait_cmd valueForKey:@"clear_mask"] intValue] :
                [[wait_cmd valueForKey:@"set_mask"] intValue] :
                &ibsta : [[wait_cmd valueForKey:@"usec_timeout"] intValue] : desc];
    [wait_cmd setValue:[NSNumber numberWithInt:ibsta] forKey:@"ibsta"];
    
    if( retval < 0 ) return retval;
    
    return 0;
}

-(int) parallel_poll_ioctl:(uint8_t *) poll_byte
{
    int retval;
    
    retval = [self ibrpp:poll_byte];
    if( retval < 0 )
        return retval;
    
    return 0;
}

-(int) online_ioctl:(BOOL) online
{
    int retval;
    if(online)
        retval = [self ibonline];
    else
        retval = [self iboffline];
    return retval;
}

-(int) remote_enable_ioctl:(BOOL) enable
{
    return [self ibsre:enable];
}

-(int) take_control_ioctl:(BOOL) synchronous
{
    return [self ibcac:synchronous];
}

-(int) line_status_ioctl:(short *) lines
{
    int retval;
    retval = [self iblines:lines];
    if( retval < 0 )
        return retval;
    return 0;
}

-(int) pad_ioctl:(unsigned int) handle : (unsigned int) pad
{
    int retval;
    gpib_descriptor *desc;
    desc = [self handle_to_descriptor:handle];
    if( desc == NULL )
        return -EINVAL;
    
    if( desc->is_board )
    {
        retval = [self ibpad:desc->pad];
        if( retval < 0 ) return retval;
    }
    else
    {
        retval = [m_board decrement_open_device_count:desc->pad : desc->sad];
        if( retval < 0 )
            return retval;
        
        desc->pad = pad;
        
        retval = [m_board increment_open_device_count:desc->pad : desc->sad];
        if( retval < 0 )
            return retval;
    }
    
    return 0;
}

-(int) sad_ioctl:(unsigned int) handle : (unsigned int) sad
{
    int retval;
    gpib_descriptor *desc;
    
    desc = [self handle_to_descriptor:handle];
    if( desc == NULL )
        return -EINVAL;
    
    if( desc->is_board )
    {
        retval = [self ibsad: sad];
        if( retval < 0 ) return retval;
    }else
    {
        retval = [m_board decrement_open_device_count:desc->pad : desc->sad];
        if( retval < 0 )
            return retval;
        
        desc->sad = sad;
        
        retval = [m_board increment_open_device_count:desc->pad : desc->sad];
        if( retval < 0 )
            return retval;
    }
    return 0;
}

-(int) eos_ioctl:(int) eos : (int) eos_flags
{
    return [self ibeos:eos : eos_flags];
}

-(int) request_service_ioctl:(unsigned int) status_byte
{
    return [self ibrsv:status_byte];
}

-(int) autospoll_ioctl:(BOOL) enable
{
    int retval = 0;
    
    /*FIXME: should keep track of whether autospolling is on or off
     * by descriptor.  That would also allow automatic decrement
     * of autospollers when descriptors are closed. */
    if(enable)
        [m_board setAutoSpoll:[m_board getAutoSpoll]+1];
    else
    {
        if([m_board getAutoSpoll] <= 0)
        {
            GPIB_DPRINTK("gpib: tried to set number of autospollers negative\n");
            retval = -EINVAL;
        }else
        {
            [m_board setAutoSpoll:[m_board getAutoSpoll]-1];
            retval = 0;
        }
    }
    return retval;
}

-(int) mutex_ioctl:(BOOL) lock_mutex
{
    /*   int retval = 0;
     
     if( lock_mutex )
     {
     retval = ![board->user_mutex tryLock];
     if(retval)
     {
     GPIB_DPRINTK("gpib: ioctl interrupted while waiting on lock\n");
     return -ERESTARTSYS;
     }
     
     spin_lock(&board->locking_pid_spinlock);
     board->locking_pid = current->pid;
     spin_unlock(&board->locking_pid_spinlock);
     
     atomic_flag_test_and_set(&board->priv->holding_mutex);
     GPIB_DPRINTK("locked board %d mutex\n", board->minor);
     }else
     {
     spin_lock(&board->locking_pid_spinlock);
     if( current->pid != board->locking_pid )
     {
     printk( "gpib: bug! pid %i tried to release mutex held by pid %i\n",
     current->pid, board->locking_pid );
     spin_unlock(&board->locking_pid_spinlock);
     return -EPERM;
     }
     board->locking_pid = 0;
     spin_unlock(&board->locking_pid_spinlock);
     
     atomic_set(&file_priv->holding_mutex, 0);
     
     mutex_unlock( &board->user_mutex );
     GPIB_DPRINTK("unlocked board %i mutex\n", board->minor);
     }
     */
    
    return 0;
}

-(int) timeout_ioctl:(unsigned int) timeout
{
    [m_board setUsecTimeout:timeout];
    //GPIB_DPRINTK( "timeout set to %i usec\n", timeout );
    return 0;
}

-(int) status_bytes_ioctl:(unsigned int *) num_bytes : (unsigned int) pad : (int) sad
{
    gpib_status_queue *device;
    
    device = [m_board get_gpib_status_queue: pad : sad];
    if( device == NULL )
        *num_bytes = 0;
    else
        *num_bytes = [m_board num_status_bytes:device];
    return 0;
}

-(int) board_info_ioctl:(board_info_ioctl_t *) info
{
    [m_board getBoardInfo: info];
    return 0;
}

-(int) ppc_ioctl:(unsigned int) config : (BOOL) set_ist : (BOOL) clear_ist
{
    int retval;
    
    if( set_ist )
    {
        [m_board setIst:1];
        [m_board parallel_poll_response:1];
    }else if( clear_ist )
    {
        [m_board setIst:0];
        [m_board parallel_poll_response:0];
    }
    
    if( config )
    {
        retval = [self ibppc:config];
        if( retval < 0 ) return retval;
    }
    
    return 0;
}

-(int) query_board_rsv_ioctl:(int *) status;
{
    *status = [m_board serial_poll_status];
    return 0;
}

-(int) interface_clear_ioctl:(unsigned int) usec_duration
{
    return [self ibsic:usec_duration];
}

-(int) request_system_control_ioctl:(BOOL) request_control
{
    [self ibrsc:request_control];
    return 0;
}

-(int) t1_delay_ioctl:(unsigned int) delay
{

    [m_board setT1NanoNsec:delay];
    
    return 0;
}

-(int) ibloc
{
    [m_board return_to_local];
    return 0;
}

-(BOOL) isAutoSpoll
{
    return m_autospoll;
}
-(void) setAutoSpoll:(BOOL) enable
{
    m_autospoll = enable;
}

@end
