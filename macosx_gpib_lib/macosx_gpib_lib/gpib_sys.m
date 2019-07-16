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

#import "gpib_sys.h"

static const unsigned int serial_timeout = 1000000;

@implementation gpib_link_arg
-(id) init
{
    self = [super init];
    //pthread_mutex_init(&lock, NULL);
    return self;
}
@end;

@implementation gpib_sys

-(void) init_gpib_sys:(Class) classBoard
{
    m_board = [[classBoard alloc] init_gpib_board];
    m_descriptors = [[NSMutableArray alloc] init];
    pthread_mutex_init(&m_user_mutex, NULL);
    pthread_mutex_init(&m_descriptors_mutex, NULL);
}

-(void) getBoardName:(gpib_link_arg*) arg
{
    arg->name = [m_board getName];
}

/*
 * DVRSP
 * This function performs a serial poll of the device with primary
 * address pad and secondary address sad. If the device has no
 * secondary adddress, pass a negative number in for this argument.  At the
 * end of a successful serial poll the response is returned in result.
 * SPD and UNT are sent at the completion of the poll.
 */
-(int) dvrsp : (unsigned int) pad : (int) sad : (unsigned int) usec_timeout : (uint8_t *) result
{
    int status = [self ibstatus];
    int retval;
    
    if( ( status & CIC ) == 0 )
    {
        GPIB_DPRINTK("gpib: not CIC during serial poll\n");
        return -1;
    }
    
    if( pad > gpib_addr_max || sad > gpib_addr_max )
    {
        GPIB_DPRINTK("gpib: bad address for serial poll");
        return -1;
    }
    
    retval = [self serial_poll_single:pad : sad : usec_timeout : result];
    if( [m_board io_timed_out] ) retval = -ETIMEDOUT;
    
    return retval;
}

/*
 * IBCAC
 * Return to the controller active state from the
 * controller standby state, i.e., turn ATN on.  Note
 * that in order to enter the controller active state
 * from the controller idle state, ibsic must be called.
 * If v is non-zero, take control synchronously, if
 * possible.  Otherwise, take control asynchronously.
 */
-(int) ibcac : (int) sync
{
    int status = [self ibstatus];
    int retval;
    
    if( ( status & CIC ) == 0 )
    {
        GPIB_DPRINTK("gpib: not CIC during ibcac()\n");
        return -1;
    }
    
    if( status & ATN )
    {
        return 0;
    }
    
    retval = [m_board take_control:sync];
    if( retval < 0 )
        GPIB_DPRINTK("gpib: error while becoming active controller\n");
    
    [m_board update_status:0];
    
    return retval;
}

/*
 * IBCMD
 * Write cnt command bytes from buf to the GPIB.  The
 * command operation terminates only on I/O complete.
 *
 * NOTE:
 *      1.  Prior to beginning the command, the interface is
 *          placed in the controller active state.
 *      2.  Before calling ibcmd for the first time, ibsic
 *          must be called to initialize the GPIB and enable
 *          the interface to leave the controller idle state.
 */
-(SInt32) ibcmd : (UInt8 *) buf : (UInt32) length : (UInt32 *) bytes_written
{
    int ret = 0;
    int status;
    
    *bytes_written = 0;
    
    status = [self ibstatus];
    
    if((status & CIC) == 0)
    {
        GPIB_DPRINTK("gpib: cannot send command when not controller-in-charge status is %d\n", status);
        return -EIO;
    }
    
    [m_board osStartTimer];
    
    ret = [self ibcac:0];
    if( ret == 0 )
    {
        ret = [m_board command:buf : length : bytes_written];
    }
    
    [m_board osRemoveTimer];
    
    if([m_board io_timed_out])
        ret = -ETIMEDOUT;
    
    return ret;
}

/*
 * IBRD
 * Read up to 'length' bytes of data from the GPIB into buf.  End
 * on detection of END (EOI and or EOS) and set 'end_flag'.
 *
 * NOTE:
 *      1.  The interface is placed in the controller standby
 *          state prior to beginning the read.
 *      2.  Prior to calling ibrd, the intended devices as well
 *          as the interface board itself must be addressed by
 *          calling ibcmd.
 */

-(int) ibrd : (UInt8 *) buf : (UInt32) length : (BOOL *) end_flag : (UInt32 *) nbytes_read
{
    int ret = 0;
    int retval;
    UInt32 bytes_read;
    
    *nbytes_read = 0;
    *end_flag = NO;
    if( length == 0 )
    {
        GPIB_DPRINTK("gpib: ibrd() called with zero length?\n");
        return 0;
    }
    
    if( [m_board isMaster] )
    {
        retval = [self ibgts];
        if( retval < 0 ) return retval;
    }
    /* XXX reseting timer here could cause timeouts take longer than they should,
     * since read_ioctl calls this
     * function in a loop, there is probably a similar problem with writes/commands */
    [m_board osStartTimer];
    do
    {
        ret = [m_board read:buf : length - *nbytes_read : end_flag : &bytes_read];
        if(ret < 0)
        {
            //printk("gpib read error\n");
        }
        buf += bytes_read;
        *nbytes_read += bytes_read;

    }while(ret == 0 && *nbytes_read > 0 && *nbytes_read < length && *end_flag == 0);
    [m_board osRemoveTimer];
    return ret;
}


/*
 * IBWRT
 * Write cnt bytes of data from buf to the GPIB.  The write
 * operation terminates only on I/O complete.
 *
 * NOTE:
 *      1.  Prior to beginning the write, the interface is
 *          placed in the controller standby state.
 *      2.  Prior to calling ibwrt, the intended devices as
 *          well as the interface board itself must be
 *          addressed by calling ibcmd.
 */
-(SInt32) ibwrt : (UInt8 *) buf : (UInt32) cnt : (BOOL) send_eoi : (UInt32 *) bytes_written
{
    int ret = 0;
    int retval;
    
    if( cnt == 0 )
    {
        GPIB_DPRINTK("gpib: ibwrt() called with zero length?\n");
        return 0;
    }
    
    if( [m_board isMaster] )
    {
        retval = [self ibgts];
        if( retval < 0 ) return retval;
    }
    [m_board osStartTimer];
    ret = [m_board write:buf : cnt : send_eoi : bytes_written];
    
    if([m_board io_timed_out])
        ret = -ETIMEDOUT;
    
    [m_board osRemoveTimer];
    
    return ret;
}

/*
 * IBGTS
 * Go to the controller standby state from the controller
 * active state, i.e., turn ATN off.
 */
-(int) ibgts
{
    int status = [self ibstatus];
    int retval;
    
    if( ( status & CIC ) == 0 )
    {
        GPIB_DPRINTK("gpib: not CIC during ibgts()\n" );
        return -1;
    }
    
    retval = [m_board go_to_standby];                    /* go to standby */
    if( retval < 0 )
        GPIB_DPRINTK("gpib: error while going to standby\n");
    
    [m_board update_status:0];
    
    return retval;
}

-(int) ibstatus
{
    return [self general_ibstatus:NULL : 0 : 0 : NULL];
}

-(int) general_ibstatus : (gpib_status_queue *) device : (int) clear_mask : (int) set_mask : (gpib_descriptor *) desc
{
    int status = 0;
    short line_status;

    status = [m_board update_status:clear_mask];
    /* XXX should probably stop having drivers use TIMO bit in
     * board->status to avoid confusion */
    status &= ~TIMO;
    /* get real SRQI status if we can */
    if([self iblines:&line_status] == 0)
    {
        if((line_status & ValidSRQ))
        {
            if((line_status & BusSRQ))
            {
                status |= SRQI;
            }else
            {
                status &= ~SRQI;
            }
        }
    }

    if( device )
        if( [m_board num_status_bytes: device] ) status |= RQS;
    
    if( desc )
    {
        if(atomic_flag_test_and_set(&desc->io_in_progress))
            status &= ~CMPL;
        else
            status |= CMPL;
        if( set_mask & CMPL )
            atomic_flag_test_and_set(&desc->io_in_progress);
        else if( clear_mask & CMPL )
            atomic_flag_clear(&desc->io_in_progress);
    }
    return status;
}

/*
 * IBLINES
 * Poll the GPIB control lines and return their status in buf.
 *
 *      LSB (bits 0-7)  -  VALID lines mask (lines that can be monitored).
 * Next LSB (bits 8-15) - STATUS lines mask (lines that are currently set).
 *
 */
-(int) iblines:(short *) lines
{
    int retval;
    
    *lines = 0;
    retval = [m_board line_status];
    if(retval < 0) return retval;
    *lines = retval;
    return 0;
}

-(int) ibonline
{
    int retval;
    
    if( [m_board isOnline] ) return -EBUSY;
    
    retval = [m_board attach];
    if(retval < 0)
    {
        [m_board detach];
        GPIB_DPRINTK("gpib: interface attach failed\n");
        return retval;
    }

    [m_board setOnline:YES];
    GPIB_DPRINTK( "gpib: board online\n" );
    
    return 0;
}

-(int) iboffline
{
    if( [m_board isOnline] == NO )
    {
        return 0;
    }
    
    [m_board detach];
    [m_board gpib_deallocate_board];
    [m_board setOnline:NO];
    GPIB_DPRINTK( "gpib: board offline\n" );
    
    return 0;
}

/*
 * IBSIC
 * Send IFC for at least 100 microseconds.
 *
 * NOTE:
 *      1.  Ibsic must be called prior to the first call to
 *          ibcmd in order to initialize the bus and enable the
 *          interface to leave the controller idle state.
 */
-(int) ibsic : (unsigned int) usec_duration
{
    if( [m_board isMaster] == 0 )
    {
        GPIB_DPRINTK("gpib: tried to assert IFC when not system controller\n");
        return -1;
    }
    
    if( usec_duration < 100 ) usec_duration = 100;
    if( usec_duration > 1000 )
    {
        usec_duration = 1000;
        GPIB_DPRINTK("gpib: warning, shortening long udelay\n");
    }
    
    GPIB_DPRINTK( "sending interface clear\n" );
    [m_board interface_clear:YES];
    usleep(usec_duration);
    [m_board interface_clear:NO];
    
    return 0;
}

-(void) ibrsc : (BOOL) request_control
{
    [m_board setMaster: request_control];
    [m_board request_system_control:request_control];
}

/*
 * IBWAIT
 * Check or wait for a GPIB event to occur.  The mask argument
 * is a bit vector corresponding to the status bit vector.  It
 * has a bit set for each condition which can terminate the wait
 * If the mask is 0 then
 * no condition is waited for.
 */
-(int) ibwait : (int) wait_mask : (int) clear_mask : (int) set_mask : (int *) status : (unsigned long) usec_timeout : (gpib_descriptor *) desc
{
    int retval = 0;
    gpib_status_queue *status_queue;
    struct wait_info winfo;
    
    if( desc->is_board ) status_queue = NULL;
    else status_queue = [m_board get_gpib_status_queue:desc->pad : desc->sad];
    
    if( wait_mask == 0 )
    {
        *status = [self general_ibstatus:status_queue : clear_mask : set_mask : desc];
        return 0;
    }
    
    [m_board init_wait_info: &winfo];
    winfo.usec_timeout = usec_timeout;
    [m_board startWaitTimer: &winfo];

    while(winfo.timed_out==NO)
    {
        CFRunLoopRunInMode(kCFRunLoopDefaultMode, 0, YES);
        if([self wait_satisfied :&winfo : status_queue : wait_mask : status :desc ] == 1)
            break;
    }

    if(winfo.timed_out==YES)
    {
        GPIB_DPRINTK("wait interrupted\n");
        retval = -ERESTARTSYS;
    }
    [m_board removeWaitTimer: &winfo];
    
    if(retval) return retval;
    
    /* make sure we only clear status bits that we are reporting */
    if( *status & clear_mask || set_mask )
        [self general_ibstatus:status_queue : *status & clear_mask : set_mask : 0];
    
    return 0;
}

/*
 * IBRPP
 * Conduct a parallel poll and return the byte in buf.
 *
 * NOTE:
 *      1.  Prior to conducting the poll the interface is placed
 *          in the controller active state.
 */
-(int) ibrpp : (uint8_t *) result
{
    int retval = 0;
    
    [m_board osStartTimer];
    retval = [self ibcac:0];
    if( retval ) return -1;
    
    if([m_board parallel_poll:result])
    {
        GPIB_DPRINTK("gpib: parallel poll failed\n");
        retval = -1;
    }
    [m_board osRemoveTimer];
    return retval;
}

-(int) ibppc : (unsigned int) configuration
{
    configuration &= 0x1f;
    [m_board parallel_poll_configure:configuration];
    [m_board setPPConfig:configuration];
    return 0;
}

/*
 * IBSRE
 * Send REN true if v is non-zero or false if v is zero.
 */
-(int) ibsre : (BOOL) enable
{
    if(	[m_board isMaster] == 0 )
    {
        GPIB_DPRINTK("gpib: tried to set REN when not system controller\n" );
        return -1;
    }
    [m_board remote_enable:enable];	/* set or clear REN */
    if( !enable )
        usleep(100);
    return 0;
}

/*
 * IBRSV
 * Request service from the CIC and/or set the serial poll
 * status byte.
 */
-(int) ibrsv : (unsigned int)  poll_status
{
    int status = [self ibstatus];
    
    if( ( status & CIC ) )
    {
        GPIB_DPRINTK("gpib: interface requested service while CIC\n");
        return -EINVAL;
    }
    
    [m_board serial_poll_response:poll_status];
    
    return 0;
}

/*
 * IBPAD
 * change the GPIB address of the interface board.  The address
 * must be 0 through 30.  ibonl resets the address to PAD.
 */
-(int) ibpad :  (unsigned int) addr
{
    if ( addr > 30 )
    {
        GPIB_DPRINTK("gpib: invalid primary address %u\n", addr );
        return -1;
    }else
    {
        [m_board setPad:addr];
        if( [m_board isOnline] )
            [m_board primary_address:addr];
        GPIB_DPRINTK( "set primary addr to %i\n", addr);
    }
    return 0;
}


/*
 * IBSAD
 * change the secondary GPIB address of the interface board.
 * The address must be 0 through 30, or negative disables.  ibonl resets the
 * address to SAD.
 */
-(int) ibsad : (int) addr
{
    if( addr > 30 )
    {
        GPIB_DPRINTK("gpib: invalid secondary address %i, must be 0-30\n", addr);
        return -1;
    }else
    {
        [m_board setSad:addr];
        if( [m_board isOnline] )
        {
            if( [m_board getSad] >= 0 )
            {
                [m_board secondary_address:addr : YES];
            }else
            {
                [m_board secondary_address:0 : NO];
            }
        }
        GPIB_DPRINTK( "set secondary addr to %i\n", addr);
    }
    return 0;
}

/*
 * IBEOS
 * Set the end-of-string modes for I/O operations to v.
 *
 */
-(int) ibeos : (int) eos : (int) eosflags
{
    int retval;
    if( eosflags & ~EOS_MASK )
    {
        GPIB_DPRINTK("bad EOS modes\n" );
        return -EINVAL;
    }else
    {
        if( eosflags & REOS )
        {
            retval = [m_board enable_eos:eos : eosflags & BIN];
        }else
        {
            [m_board disable_eos];
            retval = 0;
        }
    }
    return retval;
}


// AutoSpoll.m
-(int) autopoll_all_devices
{
    int retval;
    
    GPIB_DPRINTK( "entered autopoll_all_devices()\n" );
    if( pthread_mutex_lock(&m_user_mutex) )
    {
        return -ERESTARTSYS;
    }
    GPIB_DPRINTK( "autopoll has board lock\n" );
    
    retval = [self serial_poll_all: serial_timeout];
    if( retval < 0 )
    {
        pthread_mutex_unlock(&m_user_mutex);
        return retval;
    }
    
    GPIB_DPRINTK( "autopoll_all_devices() complete\n" );
    /* need to wake wait queue in case someone is
     * waiting on RQS */
    CFRunLoopSourceSignal(m_board->m_private_board.wait);
    CFRunLoopWakeUp(m_board->m_private_board.runner);
    pthread_mutex_unlock(&m_user_mutex);
    
    return retval;
}


// Device.m

-(SInt32) setup_serial_poll : (unsigned int) usec_timeout
{
    UInt8 cmd_string[8];
    UInt16 i;
    UInt32 bytes_written;
    SInt32 ret;
    
    GPIB_DPRINTK( "entering setup_serial_poll()\n" );
    
    [self ibcac: 0];
    
    i = 0;
    cmd_string[ i++ ] = UNL;
    cmd_string[ i++ ] = MLA([m_board getPad]);	/* controller's listen address */
    if( [m_board getSad] >= 0 )
        cmd_string[ i++ ] = MSA( [m_board getSad]);
    cmd_string[ i++ ] = SPE;	//serial poll enable
    
    [m_board osStartTimer:usec_timeout];
    ret = [m_board command:cmd_string : i : &bytes_written];
    if(ret < 0 || bytes_written < i )
    {
        GPIB_DPRINTK("gpib: failed to setup serial poll\n");
        [m_board osRemoveTimer];
        return -EIO;
    }
    [m_board osRemoveTimer];
    
    return 0;
}

-(int) read_serial_poll_byte : (unsigned int) pad : (int) sad :(unsigned int) usec_timeout : (uint8_t *) result
{
    uint8_t cmd_string[8];
    BOOL end_flag;
    int ret;
    int i;
    UInt32 nbytes_read;
    
    GPIB_DPRINTK( "entering read_serial_poll_byte(), pad=%i sad=%i\n", pad, sad );
    
    [self ibcac:0];
    
    i = 0;
    // send talk address
    cmd_string[i++] = MTA( pad );
    if( sad >= 0 )
        cmd_string[i++] = MSA( sad );
    
    [m_board osStartTimer:usec_timeout];
    ret = [m_board command:cmd_string : i : &nbytes_read];
    if( ret < 0 || nbytes_read < i )
    {
        GPIB_DPRINTK("gpib: failed to setup serial poll\n");
        [m_board osRemoveTimer];
        return -EIO;
    }
    
    [self ibgts];
    
    // read poll result
    ret = [m_board read:result : 1 : &end_flag : &nbytes_read];
    if( ret < 0 || nbytes_read < 1)
    {
        GPIB_DPRINTK("gpib: serial poll failed\n" );
        [m_board osRemoveTimer];
        return -EIO;
    }
    [m_board osRemoveTimer];
    
    return 0;
}

-(SInt32) cleanup_serial_poll : (UInt32) usec_timeout
{
    uint8_t cmd_string[8];
    SInt32 ret;
    UInt32 bytes_written;
    
    GPIB_DPRINTK( "entering cleanup_serial_poll()\n" );
    
    [self ibcac:0];
    
    cmd_string[ 0 ] = SPD;	/* disable serial poll bytes */
    cmd_string[ 1 ] = UNT;
    [m_board osStartTimer:usec_timeout];
    ret = [m_board command:cmd_string : 2 : &bytes_written];
    if( ret < 0 || bytes_written < 2 )
    {
        GPIB_DPRINTK("gpib: failed to disable serial poll\n" );
        [m_board osRemoveTimer];
        return -EIO;
    }
    [m_board osRemoveTimer];
    
    return 0;
}

-(int) serial_poll_single : (unsigned int) pad : (int) sad :(unsigned int) usec_timeout : (uint8_t *) result
{
    int retval, cleanup_retval;
    retval = [self setup_serial_poll:usec_timeout];
    if( retval < 0 )
        return retval;
    retval = [self read_serial_poll_byte:pad : sad : usec_timeout : result];
    cleanup_retval = [self cleanup_serial_poll: usec_timeout];
    if( retval < 0 )
        return retval;
    if( cleanup_retval < 0 )
        return cleanup_retval;
    return 0;
}

-(int) serial_poll_all : (unsigned int) usec_timeout
{
    int retval = 0;
    gpib_descriptor *desc;
    gpib_status_queue* device;
    uint8_t result;
    unsigned int num_bytes = 0;
    
    GPIB_DPRINTK( "entering serial_poll_all()\n" );
    
    if([m_descriptors count] == 0)
    {
        return 0;
    }
    
    retval = [self setup_serial_poll:usec_timeout];
    if( retval < 0 ) return retval;
    
    for(int index = 0; index < [m_descriptors count]; index ++)
    {
        desc = (gpib_descriptor*)[m_descriptors objectAtIndex:index];
        retval = [self read_serial_poll_byte:desc->pad : desc->sad : usec_timeout : &result];
        if( retval < 0 ) continue;
        if( result & request_service_bit )
        {
            device = [m_board get_gpib_status_queue:desc->pad : desc->sad];
            retval = [m_board push_status_byte: device : result];
            if( retval < 0 ) continue;
            num_bytes++;
        }
    }
    
    retval = [self cleanup_serial_poll:usec_timeout];
    if( retval < 0 ) return retval;
    
    return num_bytes;
}

-(int) get_serial_poll_byte : (unsigned int) pad : (int) sad : (unsigned int) usec_timeout : (uint8_t *)poll_byte
{
    
    gpib_status_queue *device;
    
    GPIB_DPRINTK( "entering get_serial_poll_byte()\n" );
    
    device = [m_board get_gpib_status_queue:pad : sad];
    if( [m_board num_status_bytes: device] )
    {
        return [m_board pop_status_byte:device : poll_byte];
    }else
    {
        return [self dvrsp:pad : sad : usec_timeout : poll_byte];
    }
}

-(int) wait_satisfied:(struct wait_info *) winfo : (gpib_status_queue *) status_queue : (int) wait_mask : (int *) status : (gpib_descriptor *) desc
{
    int temp_status;
    temp_status = [self general_ibstatus:status_queue : 0 : 0 : desc];
    
    if( winfo->timed_out )
        temp_status |= TIMO;
    else
        temp_status &= ~TIMO;
    if( wait_mask & temp_status )
    {
        *status = temp_status;
        return 1;
    }
    //XXX does wait for END work?
    return 0;
}

-(gpib_descriptor*) handle_to_descriptor:(int) handle
{
    if( handle < 0 || handle >= GPIB_MAX_NUM_DESCRIPTORS )
    {
        GPIB_DPRINTK("gpib: invalid handle %i\n", handle );
        return NULL;
    }
    
    return (gpib_descriptor*)[m_descriptors objectAtIndex:handle];
}

-(int) cleanup_open_devices
{
    int retval = 0;
    gpib_descriptor *desc;
    
    for(int index = 0; index < [m_descriptors count]; index ++)
    {
        desc = (gpib_descriptor*)[m_descriptors objectAtIndex:index];
        if( desc->is_board == NO )
        {
            retval = [m_board decrement_open_device_count:desc->pad : desc->sad];
            if( retval < 0 ) return retval;
        }
        [m_descriptors removeObject:desc];
        //[desc release];
    }
    
    return 0;
}

-(void) init_gpib_descriptor:(gpib_descriptor *) desc
{
    desc->pad = 0;
    desc->sad = -1;
    desc->is_board = NO;
    atomic_flag_clear(&desc->io_in_progress);
}

-(BOOL) use_event_queue
{
    return m_use_event_queue;
}

@end
