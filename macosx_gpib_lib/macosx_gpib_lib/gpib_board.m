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

#import "gpib_board.h"

void watchdog_timeout(CFRunLoopTimerRef timer, void *info)
{
    private_board *board = (private_board*) info;
    [gpib_board set_bit:TIMO_NUM : &board->status];
    CFRunLoopSourceSignal(board->wait);
    CFRunLoopWakeUp(board->runner);
}

static void wait_timeout(CFRunLoopTimerRef timer, void *info)
/* Watchdog timeout routine */
{
    struct wait_info *winfo = (struct wait_info*) info;
    winfo->timed_out = YES;
    CFRunLoopSourceSignal(winfo->board->wait);
    CFRunLoopWakeUp(winfo->board->runner);
}

@implementation gpib_status_queue
@end
@implementation gpib_descriptor
@end

@implementation gpib_board

-(NSString *)getName
{
    if(m_name != nil)
        return m_name;
    else
        return @"";
}
-(SInt32) attach
{
    @throw [NSException exceptionWithName:NSInternalInconsistencyException
                                   reason:[NSString stringWithFormat:@"You must override %@ in a subclass", NSStringFromSelector(_cmd)]
                                 userInfo:nil];
}
-(void) detach
{
    [NSException raise:NSInternalInconsistencyException
                format:@"You must override %@ in a subclass", NSStringFromSelector(_cmd)];
}
-(SInt32) read:(UInt8 *) buffer : (UInt32) length : (BOOL *) end : (UInt32 *) nbytes_read
{
    @throw [NSException exceptionWithName:NSInternalInconsistencyException
                                   reason:[NSString stringWithFormat:@"You must override %@ in a subclass", NSStringFromSelector(_cmd)]
                                 userInfo:nil];
}
-(SInt32) write:(UInt8 *) buffer : (UInt32) length : (BOOL) send_eoi : (UInt32 *) bytes_written
{
    @throw [NSException exceptionWithName:NSInternalInconsistencyException
                                   reason:[NSString stringWithFormat:@"You must override %@ in a subclass", NSStringFromSelector(_cmd)]
                                 userInfo:nil];
}
-(SInt32) command:(UInt8 *)buffer : (UInt32) length : (UInt32 *) bytes_written
{
    @throw [NSException exceptionWithName:NSInternalInconsistencyException
                                   reason:[NSString stringWithFormat:@"You must override %@ in a subclass", NSStringFromSelector(_cmd)]
                                 userInfo:nil];
}
-(SInt32) take_control:(BOOL) asyncronous
{
    @throw [NSException exceptionWithName:NSInternalInconsistencyException
                                   reason:[NSString stringWithFormat:@"You must override %@ in a subclass", NSStringFromSelector(_cmd)]
                                 userInfo:nil];
}
-(SInt32) go_to_standby
{
    @throw [NSException exceptionWithName:NSInternalInconsistencyException
                                   reason:[NSString stringWithFormat:@"You must override %@ in a subclass", NSStringFromSelector(_cmd)]
                                 userInfo:nil];
}
-(SInt32) request_system_control:(BOOL) request_control
{
    @throw [NSException exceptionWithName:NSInternalInconsistencyException
                                   reason:[NSString stringWithFormat:@"You must override %@ in a subclass", NSStringFromSelector(_cmd)]
                                 userInfo:nil];
}
-(SInt32) interface_clear:(BOOL) assert
{
    @throw [NSException exceptionWithName:NSInternalInconsistencyException
                                   reason:[NSString stringWithFormat:@"You must override %@ in a subclass", NSStringFromSelector(_cmd)]
                                 userInfo:nil];
}
-(SInt32) remote_enable:(BOOL) enable
{
    @throw [NSException exceptionWithName:NSInternalInconsistencyException
                                   reason:[NSString stringWithFormat:@"You must override %@ in a subclass", NSStringFromSelector(_cmd)]
                                 userInfo:nil];
}
-(SInt32) enable_eos:(uint8_t) eos : (BOOL) compare_8_bits
{
    @throw [NSException exceptionWithName:NSInternalInconsistencyException
                                   reason:[NSString stringWithFormat:@"You must override %@ in a subclass", NSStringFromSelector(_cmd)]
                                 userInfo:nil];
}
-(void) disable_eos
{
    [NSException raise:NSInternalInconsistencyException
                format:@"You must override %@ in a subclass", NSStringFromSelector(_cmd)];
}
-(void) parallel_poll_configure:(uint8_t) configuration
{
    [NSException raise:NSInternalInconsistencyException
                format:@"You must override %@ in a subclass", NSStringFromSelector(_cmd)];
}
-(SInt32) parallel_poll:(uint8_t *) result
{
    @throw [NSException exceptionWithName:NSInternalInconsistencyException
                                   reason:[NSString stringWithFormat:@"You must override %@ in a subclass", NSStringFromSelector(_cmd)]
                                 userInfo:nil];
}
-(void) parallel_poll_response:(UInt32) ist
{
    [NSException raise:NSInternalInconsistencyException
                format:@"You must override %@ in a subclass", NSStringFromSelector(_cmd)];
}
-(SInt32) line_status
{
    @throw [NSException exceptionWithName:NSInternalInconsistencyException
                                   reason:[NSString stringWithFormat:@"You must override %@ in a subclass", NSStringFromSelector(_cmd)]
                                 userInfo:nil];
}
-(UInt32) update_status:(UInt32) clear_mask
{
    @throw [NSException exceptionWithName:NSInternalInconsistencyException
                                   reason:[NSString stringWithFormat:@"You must override %@ in a subclass", NSStringFromSelector(_cmd)]
                                 userInfo:nil];
}
-(SInt32) primary_address:(UInt16) address
{
    @throw [NSException exceptionWithName:NSInternalInconsistencyException
                                   reason:[NSString stringWithFormat:@"You must override %@ in a subclass", NSStringFromSelector(_cmd)]
                                 userInfo:nil];
}
-(void) secondary_address:(UInt16) address : (BOOL) enable
{
    [NSException raise:NSInternalInconsistencyException
                format:@"You must override %@ in a subclass", NSStringFromSelector(_cmd)];
}
-(void) serial_poll_response:(UInt8) status
{
    [NSException raise:NSInternalInconsistencyException
                format:@"You must override %@ in a subclass", NSStringFromSelector(_cmd)];
}
-(UInt8) serial_poll_status
{
    @throw [NSException exceptionWithName:NSInternalInconsistencyException
                                   reason:[NSString stringWithFormat:@"You must override %@ in a subclass", NSStringFromSelector(_cmd)]
                                 userInfo:nil];
}
-(UInt32) t1_delay:(UInt32) nano_sec
{
    @throw [NSException exceptionWithName:NSInternalInconsistencyException
                                   reason:[NSString stringWithFormat:@"You must override %@ in a subclass", NSStringFromSelector(_cmd)]
                                 userInfo:nil];
}
-(void) return_to_local
{
    [NSException raise:NSInternalInconsistencyException
                format:@"You must override %@ in a subclass", NSStringFromSelector(_cmd)];
}


/////////////////////////////////////////////////////////////////////////////////////////////////////////

-(int) increment_open_device_count:(unsigned int) pad : (int) sad
{
    gpib_status_queue *device;
    
    /* first see if address has already been opened, then increment
     * open count */
    for(int index = 0; index < [m_device_list count]; index ++)
    {
        device = (gpib_status_queue*)[m_device_list objectAtIndex:index];
        if( gpib_address_equal( device->pad, device->sad, pad, sad ) )
        {
            GPIB_DPRINTK("incrementing open count for pad %i, sad %i\n",
                         device->pad, device->sad );
            device->reference_count++;
            return 0;
        }
    }
    
    /* otherwise we need to allocate a new gpib_status_queue_t */
    device = [[gpib_status_queue alloc] init];
    [self init_gpib_status_queue: device];
    device->pad = pad;
    device->sad = sad;
    device->reference_count = 1;
    
    [m_device_list addObject:device];
    
    GPIB_DPRINTK( "opened pad %i, sad %i\n",
                 device->pad, device->sad );
    
    return 0;
}

-(int) subtract_open_device_count:(unsigned int) pad : (int) sad : (unsigned int) count
{
    gpib_status_queue *device;
    
    for(int index = 0; index < [m_device_list count]; index ++)
    {
        device = (gpib_status_queue*)[m_device_list objectAtIndex:index];
        if( gpib_address_equal( device->pad, device->sad, pad, sad ) )
        {
            GPIB_DPRINTK( "decrementing open count for pad %i, sad %i\n",
                         device->pad, device->sad );
            if( count > device->reference_count )
            {
                GPIB_DPRINTK("gpib: bug! in subtract_open_device_count()\n" );
                return -EINVAL;
            }
            device->reference_count -= count;
            if( device->reference_count == 0 )
            {
                GPIB_DPRINTK( "closing pad %i, sad %i\n",
                             device->pad, device->sad );
                [m_device_list removeObjectAtIndex:index];
            }
            return 0;
        }
    }
    GPIB_DPRINTK("gpib: bug! tried to close address that was never opened!\n" );
    return -EINVAL;
}

-(int) decrement_open_device_count:(unsigned int) pad : (int) sad
{
    return [self subtract_open_device_count:pad : sad : 1];
}

-(void) init_gpib_status_queue:(gpib_status_queue *) device
{
    device->status_bytes = [[NSMutableArray alloc] init];
    device->num_status_bytes = 0;
    device->reference_count = 0;
    device->dropped_byte = NO;
}

/*
 * ostimer.c Timer functions
 */

-(void) osStartTimer
{
    [self osStartTimer:_usecTimeout];
}


/* install timer interrupt handler */
-(void) osStartTimer:(unsigned int) usec_timeout
{

    if( m_timer != 0)
        if( CFRunLoopTimerIsValid(m_timer))
        {
            GPIB_DPRINTK("gpib: bug! timer already running?\n");
            return;
        }
    [gpib_board clear_bit:TIMO_NUM : &m_private_board.status];
    
    if( usec_timeout > 0 )
    {
        CFRunLoopTimerContext context = { 0, &m_private_board, NULL, NULL, NULL };
        CFAbsoluteTime FireTime = CFAbsoluteTimeGetCurrent() + (usec_timeout / 1.0e6);
        m_timer = CFRunLoopTimerCreate(NULL, FireTime, 0, 0, 0, watchdog_timeout, &context);
        if (m_timer != 0) {
            CFRunLoopAddTimer(CFRunLoopGetCurrent(), m_timer, kCFRunLoopCommonModes);
        }
    }
}

-(void) osRemoveTimer
{
    if(m_timer != 0)
    {
        if( CFRunLoopTimerIsValid(m_timer))
        {
            CFRunLoopTimerInvalidate(m_timer);
        }
        CFRelease(m_timer);
        m_timer = 0;
    }
}

-(BOOL) io_timed_out
{
    if([gpib_board test_bit:TIMO_NUM : &m_private_board.status])
        return YES;
    else
        return NO;
}

// osinit.c
-(id) init_gpib_board
{
    self = [super init];
    m_name = Nil;
    _buffer = nil;
    _bufferLength = 0;
    m_private_board.status = 0;
    pthread_mutex_init(&m_big_gpib_mutex, NULL);
    m_timer = nil;
    m_device_list = [[NSMutableArray alloc] init];
    _pad = 29;
    _sad = 0;
    _usecTimeout = 3000000;
    _pPConfig = 0;
    _online = NO;
    _autoSpoll = 0;
    m_autospoll_task = NULL;
    _master = YES;
    m_private_board.runner = CFRunLoopGetCurrent(); 
    m_source_context.info = NULL;
    m_source_context.perform  = NULL;
    return self;
}

-(void) init_wait_info: (struct wait_info *) winfo
{
    winfo->timer = Nil;
    winfo->timed_out = NO;
    winfo->board = &m_private_board;
}

/* install timer interrupt handler */
-(void) startWaitTimer:(struct wait_info *) winfo
{
    winfo->timed_out = NO;

    if( winfo->timer != 0)
        if( CFRunLoopTimerIsValid(winfo->timer))
        {
            GPIB_DPRINTK("gpib: bug! timer already running?\n");
            return;
        }
    
    if( winfo->usec_timeout > 0 )
    {
        CFRunLoopTimerContext context = { 0, winfo, NULL, NULL, NULL };
        CFAbsoluteTime FireTime = CFAbsoluteTimeGetCurrent() + (winfo->usec_timeout / 1.0e6);
        winfo->timer = CFRunLoopTimerCreate(NULL, FireTime, 0, 0, 0, wait_timeout, &context);
        if (winfo->timer != 0) {
            CFRunLoopAddTimer(CFRunLoopGetCurrent(), winfo->timer, kCFRunLoopCommonModes);
        }
    }
}

-(void) removeWaitTimer:(struct wait_info *) winfo
{
    if(winfo->timer != 0)
    {
        if( CFRunLoopTimerIsValid(winfo->timer))
        {
            CFRunLoopTimerInvalidate(winfo->timer);
        }
        CFRelease(winfo->timer);
        winfo->timer = 0;
    }
}

-(int) gpib_allocate_board:(unsigned int) length
{
    if( _buffer == nil )
    {
        _bufferLength = length;//0x4000;
        _buffer = calloc(_bufferLength, sizeof(uint8_t));
    }
    if(m_private_board.wait ==0)
    {
        m_private_board.wait = CFRunLoopSourceCreate(NULL, 0, &m_source_context);
        CFRunLoopAddSource(CFRunLoopGetCurrent(), m_private_board.wait, kCFRunLoopDefaultMode);//kCFRunLoopCommonModes);
    }
    return 0;
}

-(void) gpib_deallocate_board
{
    if( _buffer )
    {
        free( _buffer );
        _buffer = nil;
        _bufferLength = 0;
    }
    if(m_private_board.wait != 0)
    {
        if(CFRunLoopSourceIsValid(m_private_board.wait))
        {
            CFRunLoopSourceInvalidate(m_private_board.wait);
            CFRelease(m_private_board.wait);
            m_private_board.wait = 0;
        }
    }
}

-(UInt32) num_status_bytes:(gpib_status_queue *) dev
{
    if(dev == NULL) return 0;
    return dev->num_status_bytes;
}

// push status byte onto back of status byte fifo
-(int) push_status_byte:(gpib_status_queue *) device : (uint8_t) poll_byte
{
    NSNumber *status_poll_byte;
    static const unsigned int max_nustatus_bytes = 1024;
    int retval;
    
    if( [self num_status_bytes: device] >= max_nustatus_bytes )
    {
        uint8_t lost_byte;
        
        device->dropped_byte = YES;
        retval = [self pop_status_byte: device : &lost_byte];
        if( retval < 0 ) return retval;
    }
    
    status_poll_byte = [[NSNumber alloc] initWithUnsignedInt:poll_byte];
    [device->status_bytes addObject:status_poll_byte];
    device->num_status_bytes++;
    
    GPIB_DPRINTK( "pushed status byte 0x%x, %i in queue\n",
                 (int) poll_byte, [self num_status_bytes: device] );
    
    return 0;
}

// pop status byte from front of status byte fifo
-(int) pop_status_byte:(gpib_status_queue *) device : (uint8_t*) poll_byte
{
    NSNumber *status_poll_byte;
    
    if( [self num_status_bytes: device] == 0 ) return -EIO;
    
    if( device->dropped_byte )
    {
        device->dropped_byte = NO;
        return -EPIPE;
    }
    
    status_poll_byte = [device->status_bytes lastObject];
    *poll_byte = [status_poll_byte unsignedIntValue];
    [device->status_bytes removeLastObject];
    //[status_poll_byte release];
    
    device->num_status_bytes--;
    
    GPIB_DPRINTK( "popped status byte 0x%x, %i in queue\n",
                 (unsigned int) *poll_byte, [self num_status_bytes:device]);
    
    return 0;
}

-(gpib_status_queue *) get_gpib_status_queue:(unsigned int) pad : (int) sad
{
    gpib_status_queue *device;
    
    for(int index = 0; index < [m_device_list count]; index ++)
    {
        device = (gpib_status_queue*)[m_device_list objectAtIndex:index];
        if( gpib_address_equal( device->pad, device->sad, pad, sad ) )
            return device;
    }
    return NULL;
}

-(void) getBoardInfo:(board_info_ioctl_t *) info
{
    info->pad = _pad;
    info->sad = _sad;
    info->parallel_poll_configuration = _pPConfig;
    info->is_system_controller = _master;
    info->autopolling = _autoSpoll;
    info->t1_delay = _t1NanoNsec;
    info->ist = _ist;
    info->no_7_bit_eos = m_no_7_bit_eos;
}

+(BOOL) test_bit:(UInt32) pos : (UInt32 *) var
{
    if(*var & (1UL<<pos))
        return YES;
    return NO;
}

+(void) set_bit:(UInt32) pos : (UInt32 *) var
{
    *var|=(1UL<<pos);
}

+(void) clear_bit:(UInt32) pos : (UInt32*) var
{
    *var&=~(1UL<<pos);
}

+(BOOL) test_and_clear_bit:(UInt32) pos : (UInt32 *) var
{
    BOOL ret = NO;
    if(*var & (1UL<<pos))
        ret =  YES;
    *var|=(1UL<<pos);
    return ret;
}
 
@end

