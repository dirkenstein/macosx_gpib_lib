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
#import "sys/stat.h"
#import "gpib_visa_internal.h"
#import "Agilent_82357_AB.h"


@implementation gpib_aio_arg
@end
@implementation async_operation
@end
@implementation ibConf_t
@end

@implementation gpib_visa_internal

-(id) init
{
    self = [super init];
    board_list = [[NSMutableArray alloc] init];
    gpib_link* board;
    int boardId = 0;
    while([board_list count]<GPIB_MAX_NUM_BOARDS+1)
    {
        board = [[gpib_link alloc] init_gpib_link:[agilent_82357_ab class]];
        [board_list addObject:board];
        boardId = (int)[board_list indexOfObject:board];
        if([self configure_board:boardId : 0 :-1 :YES :YES :YES])
        {
            [board_list removeObject:board];
            [board close];
            break;
        }
        else
        {
            printf("Found board %d: %s\n",  boardId, [[board ibname] UTF8String]);
        }
    }
    if([board_list count] == 0)
        printf("Warning: No board found!\n");
    return self;
}

-(void) close
{
    gpib_link* board;
    for(int index = 0; index < [board_list count]; index ++)
    {
        board = [board_list objectAtIndex:index];
        if(board != nil)
        {
            [board close];
            [board_list removeObject:board];
        }
        else
        {
            break;
        }
    }
}

-(int) findBoardWithName:(const char *) name
{
    gpib_link* board = nil;
    NSString *nameToFind = [[NSString alloc] initWithUTF8String:name];
    for(int index=0; index < [board_list count]; index++)
    {
        board = [board_list objectAtIndex:index];
        if(board != nil)
        {
            if([[board ibname] isEqualToString:nameToFind])
                return index;
        }
    }
    return -1;
}

-(const char*) ibBoardName:(int) boardId
{
    gpib_link* board = nil;
    if([board_list count] >= boardId+1)
    {
        board = [board_list objectAtIndex:boardId];
        if(board != nil)
        {
            return [[board ibname] UTF8String];
        }
    }
    return "";
}

-(int) boardCount
{
    return (int)[board_list count];
}

-(int) configure_board:(UInt8) boardId : (int) pad : (int) sad : (BOOL) is_system_controller : (BOOL) assert_ifc : (BOOL) assert_remote_enable
{
    int retval;
    gpib_link* board = [board_list objectAtIndex:boardId];
    gpib_link_arg* arg = [[gpib_link_arg alloc] init];
    
    if( boardId >= GPIB_MAX_NUM_BOARDS )
    {
        return -1;
    }
    
    arg->cmd = IBONL;
    arg->bOnline = YES;
    retval = [board ioctl:arg];
    if(retval < 0)
        return retval;
    
    ibConfigs[boardId] = [[ibConf_t alloc] init];
    [self init_ibconf:ibConfigs[boardId]];
    sad -= sad_offset;
    ibConfigs[boardId]->settings.pad = pad;
    ibConfigs[boardId]->settings.sad = sad;                        /* device address                   */
    ibConfigs[boardId]->settings.board = boardId;                         /* board number                     */
    ibConfigs[boardId]->defaults = ibConfigs[boardId]->settings;
    ibConfigs[boardId]->is_interface = YES;
    [self general_enter_library:boardId :YES :NO];
    
    arg->cmd = IBPAD;
    arg->pad = pad;
    retval = [board ioctl:arg];
    if( retval < 0 )
    {
        fprintf(stderr, "failed to configure pad\n");
        return retval;
    }
    
    arg->cmd = IBSAD;
    arg->sad = sad;
    retval = [board ioctl:arg];
    if( retval < 0 )
    {
        fprintf(stderr, "failed to configure sad\n");
        return retval;
    }
    
    retval = [self internal_ibrsc:ibConfigs[boardId] :is_system_controller];
    if( retval & ERR )
    {
        fprintf( stderr, "failed to request/release system control\n" );
        return -1;
    }
    if( is_system_controller )
    {
        if( assert_remote_enable )
        {
            retval = [self internal_ibsre:ibConfigs[boardId] :YES];
            if( retval & ERR )
            {
                fprintf( stderr, "failed to assert remote enable\n" );
                return -1;
            }
        }
        if( assert_ifc )
        {
            retval = [self internal_ibsic:ibConfigs[boardId]];
            if( retval & ERR )
            {
                fprintf( stderr, "failed to assert interface clear\n" );
                return -1;
            }
        }
    }
    
    return 0;
}


-(void) init_ibconf:(ibConf_t *) conf
{
    conf->handle = -1;
    memset(conf->name, 0, sizeof(conf->name));
    [self init_descriptor_settings:&conf->defaults];
    [self init_descriptor_settings:&conf->settings];
    memset(conf->init_string, 0, sizeof(conf->init_string));
    conf->flags = 0;
    conf->async = [[async_operation alloc] init];
    [self init_async_op:conf->async];
    conf->end = 0;
    conf->is_interface = YES;
    conf->board_is_open = 0;
    conf->has_lock = 0;
    conf->timed_out = 0;    
}

-(ibConf_t*) copy_ibconf:(ibConf_t *) conf
{
    ibConf_t* newConf = [[ibConf_t alloc] init];
    newConf->handle = conf->handle;
    memset(newConf->name, 0, sizeof(conf->name));
    for(int i=0; i<sizeof(conf->name); i++)
        newConf->name[i] = conf->name[i];
    newConf->defaults = conf->defaults;
    newConf->settings = conf->settings;
    memset(newConf->init_string, 0, sizeof(conf->init_string));
    for(int i=0; i<sizeof(conf->name); i++)
        newConf->init_string[i] = conf->init_string[i];
    newConf->flags = conf->flags;
    newConf->async = [[async_operation alloc] init];
    [self init_async_op:newConf->async];
    newConf->end = conf->end;
    newConf->is_interface = conf->is_interface;
    newConf->board_is_open = conf->board_is_open;
    newConf->has_lock = conf->has_lock;
    newConf->timed_out = conf->timed_out;
    return newConf;
}

-(void) init_async_op:(async_operation *) async;
{
    pthread_mutex_init( &async->lock, NULL );
    pthread_mutex_init( &async->join_lock, NULL );
    //pthread_cond_init(&async->condition, NULL);
    async->condition = nil;
    async->buffer = nil;
    async->buffer_length = 0;
    async->iberr = 0;
    async->ibsta = 0;
    async->ibcntl = 0;
    async->in_progress = NO;
    async->abort = 0;
    async->thread = nil;
}

-(int) ibGetDescriptor:(ibConf_t*) conf
{
    int retval;
    
    /* XXX should go somewhere else XXX check validity of values */
    if(conf->settings.pad > gpib_addr_max || conf->settings.sad > gpib_addr_max)
    {
        [self setIberr:ETAB];
        return -1;
    }
    
    retval = [self insert_descriptor:conf : -1];
    
    return retval;
}

-(int) insert_descriptor:(ibConf_t*) conf : (int) ud
{
    int i;
    
    if( ud < 0 )
    {
        for( i = GPIB_MAX_NUM_BOARDS; i < GPIB_CONFIGS_LENGTH; i++ )
        {
            if( ibConfigs[ i ] == nil ) break;
        }
        if( i >= GPIB_CONFIGS_LENGTH )
        {
            fprintf( stderr, "libmacosx_gpib: out of room in ibConfigs[]\n" );
            [self setIberr:ENEB]; // ETAB?
            return -1;
        }
        ud = i;
    }else
    {
        if( ud >= GPIB_CONFIGS_LENGTH )
        {
            fprintf( stderr, "libmacosx_gpib: bug! tried to allocate past end if ibConfigs array\n" );
            [self setIberr:EDVR];
            [self setIbcnt:EINVAL];
            return -1;
        }
        if( ibConfigs[ ud ] )
        {
            fprintf( stderr, "libmacosx_gpib: bug! tried to allocate board descriptor twice\n" );
            [self setIberr:EDVR];
            [self setIbcnt:EINVAL];
            return -1;
        }
    }
    /* put entry to the table */
    ibConfigs[ud] = conf;
    
    return ud;
}

-(void) init_descriptor_settings:(descriptor_settings_t *) settings
{
    settings->pad = -1;
    settings->sad = -1;
    settings->board = -1;
    settings->usec_timeout = 3000000;
    settings->spoll_usec_timeout = 1000000;
    settings->ppoll_usec_timeout = 2;
    settings->eos = 0;
    settings->eos_flags = 0;
    settings->ppoll_config = 0;
    settings->send_eoi = 1;
    settings->local_lockout = 0;
    settings->local_ppc = 0;
    settings->readdr = 0;
}

-(void) globals_alloc
{
    if (thread_key ==nil)
    {
        thread_key = [[[NSThread currentThread] threadDictionary] init];
    }
    if ([thread_key objectForKey:@"ibsta_key"] == nil)
    {
        NSNumber *ibsta_key = [[NSNumber alloc] initWithInt:0];
        [thread_key setObject:ibsta_key forKey:@"ibsta_key"];
    }
    if ([thread_key objectForKey:@"iberr_key"] == nil)
    {
        NSNumber *iberr_key = [[NSNumber alloc] initWithInt:0];
        [thread_key setObject:iberr_key forKey:@"iberr_key"];
    }
    if ([thread_key objectForKey:@"ibcntl_key"] == nil)
    {
        NSNumber *ibcntl_key = [[NSNumber alloc] initWithInt:0];
        [thread_key setObject:ibcntl_key forKey:@"ibcntl_key"];
    }
}

-(void) setIberr:(int) error
{
    [self globals_alloc];
    [thread_key setValue:[NSNumber numberWithInt:error] forKey:@"iberr_key"];
}

-(void) setIbcnt:(long) count
{
    [self globals_alloc];
    [thread_key setValue:[NSNumber numberWithLong:count] forKey:@"ibcntl_key"];
}

-(void) setIbsta:(int) status
{
    [self globals_alloc];
    [thread_key setValue:[NSNumber numberWithInt:status] forKey:@"ibsta_key"];
}

-(unsigned int) timeout_to_usec:(enum gpib_timeout) timeout
{
    switch ( timeout )
    {
        default:
        case TNONE:
            return 0;
            break;
        case T10us:
            return 10;
            break;
        case T30us:
            return 30;
            break;
        case T100us:
            return 100;
            break;
        case T300us:
            return 300;
            break;
        case T1ms:
            return 1000;
            break;
        case T3ms:
            return 3000;
            break;
        case T10ms:
            return 10000;
            break;
        case T30ms:
            return 30000;
            break;
        case T100ms:
            return 100000;
            break;
        case T300ms:
            return 300000;
            break;
        case T1s:
            return 1000000;
            break;
        case T3s:
            return 3000000;
            break;
        case T10s:
            return 10000000;
            break;
        case T30s:
            return 30000000;
            break;
        case T100s:
            return 100000000;
            break;
        case T300s:
            return 300000000;
            break;
        case T1000s:
            return 1000000000;
            break;
    }
    return 0;
}
-(unsigned int) ppoll_timeout_to_usec:(UInt32) timeout
{
    if( timeout == 0 )
        return default_ppoll_usec_timeout;
    else
        return [self timeout_to_usec:timeout];
}
-(unsigned int) usec_to_ppoll_timeout:(UInt32) usec
{
    if( usec == 0 ) return TNONE;
    else if( usec <= 10 ) return T10us;
    else if( usec <= 30 ) return T30us;
    else if( usec <= 100 ) return T100us;
    else if( usec <= 300 ) return T300us;
    else if( usec <= 1000 ) return T1ms;
    else if( usec <= 3000 ) return T3ms;
    else if( usec <= 10000 ) return T10ms;
    else if( usec <= 30000 ) return T30ms;
    else if( usec <= 100000 ) return T100ms;
    else if( usec <= 300000 ) return T300ms;
    else if( usec <= 1000000 ) return T1s;
    else if( usec <= 3000000 ) return T3s;
    else if( usec <= 10000000 ) return T10s;
    else if( usec <= 30000000 ) return T30s;
    else if( usec <= 100000000 ) return T100s;
    else if( usec <= 300000000 ) return T300s;
    else if( usec <= 1000000000 ) return T1000s;
    
    return TNONE;
}

-(gpib_link *) interfaceBoard:(ibConf_t *) conf
{
    assert( conf->settings.board >= 0 && conf->settings.board < GPIB_MAX_NUM_BOARDS );
    if([board_list count] >= conf->settings.board+1)
        return [board_list objectAtIndex:conf->settings.board];
    else return nil;
}

-(int) general_exit_library:(int) ud : (BOOL) error : (BOOL) no_sync_globals : (BOOL) no_update_ibsta : (int) status_clear_mask : (int) status_set_mask : (BOOL) no_unlock_board;
{
    ibConf_t *conf = ibConfigs[ ud ];
    int status;
    if( [self ibCheckDescriptor:ud] < 0 )
    {
        [self setIbsta:ERR];
        if( no_sync_globals == 0 )
            [self sync_globals];
        return ERR;
    }
    if( no_update_ibsta )
        status = [self ThreadIbsta];
    else
        status = [self ibstatus:conf : error : status_clear_mask : status_set_mask];
    
    if( no_unlock_board == 0 && conf->has_lock )
        [self conf_unlock_board:conf];
    
    if( no_sync_globals == 0 )
        [self sync_globals];
    
    return status;
}

-(int) ibCheckDescriptor:(int) ud
{
    if( ud < 0 || ud >= GPIB_CONFIGS_LENGTH || ibConfigs[ud] == nil )
    {
        fprintf( stderr, "libmacosx_gpib: invalid descriptor\n" );
        [self setIberr:EDVR];
        [self setIbcnt:EINVAL];
        return -1;
    }
    
    return 0;
}

-(int) conf_online:(ibConf_t *) conf : (BOOL) online
{
    int retval;
    
    if( ( online && conf->board_is_open ) ||
       ( online == 0 && conf->board_is_open == 0 ) )
        return 0;
    
    retval = [self board_online:conf->settings.board : online];
    if( retval < 0 ) return retval;
    if( online )
    {
        retval = [self open_gpib_handle:conf];
    }else
    {
        retval = [self close_gpib_handle:conf];
    }
    if( retval < 0 ) return retval;
    
    conf->board_is_open = online != 0;
    
    return 0;
}

-(int) board_online:(int) boardId : (BOOL) online
{
    if( online )
    {
        if( [self ibBoardOpen:boardId] < 0 )
            return -1;
    }else
    {
        [self ibBoardClose:boardId];
    }
    
    return 0;
}

-(ssize_t) my_ibcmd:(ibConf_t *) conf : (UInt8 *) buffer : (size_t) count
{
    int retval;
    gpib_link *board;
    gpib_link_arg* arg = [[gpib_link_arg alloc] init];
    
    board = [self interfaceBoard:conf];
    
    [self set_timeout:board : conf->settings.usec_timeout];
    
    if( [self is_cic:board] == NO )
    {
        [self setIberr:ECIC];
        return -1;
    }
    
    //assert(sizeof(buffer) <= sizeof(arg->readWrite.buffer_ptr));
    /*arg->readWrite.buffer_ptr = buffer;
    arg->readWrite.requested_transfer_count = count;
    arg->readWrite.completed_transfer_count = 0;
    arg->readWrite.handle = conf->handle;
    arg->readWrite.end = 0;
    arg->nUsecDuration = conf->settings.usec_timeout;*/
    arg->cmd = IBCMD;
    arg->read_ioctl = [[NSMutableDictionary alloc] initWithObjectsAndKeys:
                       [NSNumber numberWithInteger:conf->handle],@"handle",
                       [[NSMutableData alloc] initWithBytes:buffer length:count],@"buffer",
                       [NSNumber numberWithInteger:count],@"requested_transfer_count",
                       [NSNumber numberWithInteger:0],@"completed_transfer_count",
                       [NSNumber numberWithBool:NO],@"end",
                       nil];
    
    [self set_timeout:board : conf->settings.usec_timeout];
    
    retval = [board ioctl:arg];
    
    if( retval < 0 )
    {
        switch( errno )
        {
            case ETIMEDOUT:
                [self setIberr:EBUS];
                conf->timed_out = YES;
                break;
            default:
                [self setIberr:EDVR];
                [self setIbcnt:errno];
                break;
        }
        return -1;
    }
    
    //return arg->readWrite.completed_transfer_count;
    return [[arg->read_ioctl valueForKey:@"completed_transfer_count"] intValue];
}

-(UInt8) create_send_setup:(gpib_link *) board : (uint16_t *) addressList : (UInt8 *) cmdString
{
    UInt8 i, j;
    UInt8 board_pad;
    int board_sad;
    
    if( addressList == NULL )
    {
        fprintf(stderr, "libmacosx_gpib: bug! addressList NULL in create_send_setup()\n");
        return 0;
    }
    if( [self addressListIsValid:addressList] == NO )
    {
        fprintf(stderr, "libmacosx_gpib: bug! bad address list\n");
        return 0;
    }
    
    i = 0;
    /* controller's talk address */
    if([self query_pad:board : &board_pad] < 0) return 0;
    cmdString[i++] = MTA(board_pad);
    if([self query_sad:board : &board_sad] < 0) return 0;
    if(board_sad >= 0 )
        cmdString[i++] = MSA(board_sad);
    cmdString[ i++ ] = UNL;
    for( j = 0; j < [self numAddresses:addressList]; j++ )
    {
        UInt8 pad;
        int sad;
        
        pad = [self extractPAD:addressList[j]];
        sad = [self extractSAD:addressList[j]];
        cmdString[ i++ ] = MLA( pad );
        if( sad >= 0)
            cmdString[ i++ ] = MSA( sad );
    }
    
    return i;
}

-(UInt8) send_setup_string:(ibConf_t *) conf : (UInt8 *) cmdString
{
    gpib_link *board;
    uint16_t addressList[ 2 ];
    
    board = [self interfaceBoard:conf];
    
    addressList[ 0 ] = [self packAddress:conf->settings.pad : conf->settings.sad];
    addressList[ 1 ] = NOADDR;
    
    return [self create_send_setup:board : addressList : cmdString];
}

-(int) send_setup:(ibConf_t *) conf
{
    UInt8 cmdString[8];
    int retval;
    
    retval = [self send_setup_string:conf : cmdString];
    
    if( [self my_ibcmd:conf : cmdString : retval] < 0 )
        return -1;
    
    return 0;
}

-(int) InternalSendSetup:(ibConf_t *) conf : (uint16_t *) addressList
{
    size_t i;
    gpib_link *board;
    UInt8 *cmd;
    ssize_t count;
    
    if( [self addressListIsValid:addressList]  == NO ||
       [self numAddresses:addressList] == 0 )
    {
        [self setIberr:EARG];
        return -1;
    }
    
    if( conf->is_interface == 0 )
    {
        [self setIberr:EDVR];
        return -1;
    }
    
    board = [self interfaceBoard:conf];
    
    if( [self is_cic:board] == NO)
    {
        [self setIberr:ECIC];
        return -1;
    }
    
    cmd = malloc( 16 + 2 * [self numAddresses:addressList]);
    if( cmd == NULL )
    {
        [self setIberr:EDVR];
        [self setIbcnt:ENOMEM];
        return -1;
    }
    
    i = [self create_send_setup:board : addressList : cmd];
    
    //XXX detect no listeners (EBUS) error
    count = [self my_ibcmd:conf : cmd : i];
    
    free( cmd );
    cmd = NULL;
    
    if(count != i)
    {
        return -1;
    }
    
    return 0;
}

-(int) query_ist:(gpib_link *) board
{
    int retval;
    //board_info_ioctl_t info;
    gpib_link_arg* arg = [[gpib_link_arg alloc] init];
    
    arg->cmd = IBBOARD_INFO;
    
    //retval = ioctl( board->fileno, IBBOARD_INFO, &info );
    retval = [board ioctl:arg];
    if( retval < 0 )
    {
        [self setIberr:EDVR];
        [self setIbcnt:errno];
        return retval;
    }
    
    return arg->boardInfo.ist;
}

-(int) query_ppc:(gpib_link *) board
{
    int retval;
    //board_info_ioctl_t info;
    gpib_link_arg* arg = [[gpib_link_arg alloc] init];
    arg->cmd = IBBOARD_INFO;
    //retval = ioctl( board->fileno, IBBOARD_INFO, &info );
    retval = [board ioctl:arg];
    if( retval < 0 )
    {
        [self setIberr:EDVR];
        [self setIbcnt:errno];
        return retval;
    }
    
    return arg->boardInfo.parallel_poll_configuration;
}

-(int) query_autopoll:(gpib_link *) board
{
    int retval;
    //board_info_ioctl_t info;
    gpib_link_arg* arg = [[gpib_link_arg alloc] init];
    arg->cmd = IBBOARD_INFO;
    
    //retval = ioctl( board->fileno, IBBOARD_INFO, &info );
    retval = [board ioctl:arg];
    if( retval < 0 )
    {
        [self setIberr:EDVR];
        [self setIbcnt:errno];
        return retval;
    }
    
    return arg->boardInfo.autopolling;
}

-(int) query_board_t1_delay:(gpib_link *) board
{
    int retval;
    //board_info_ioctl_t info;
    gpib_link_arg* arg = [[gpib_link_arg alloc] init];
    arg->cmd = IBBOARD_INFO;
    
    //retval = ioctl( board->fileno, IBBOARD_INFO, &info );
    retval = [board ioctl:arg];
    if( retval < 0 )
    {
        [self setIberr:EDVR];
        [self setIbcnt:errno];
        return retval;
    }
    
    if(arg->boardInfo.t1_delay == 0)
    {
        fprintf(stderr, "%s: bug! we don't know what the T1 delay is because it has never been set.\n",
                __FUNCTION__);
        return -EIO;
    }else if( arg->boardInfo.t1_delay < 500 ) return T1_DELAY_350ns;
    else if( arg->boardInfo.t1_delay < 2000 ) return T1_DELAY_500ns;
    return T1_DELAY_2000ns;
}

-(int) query_board_rsv:(gpib_link *) board
{
    int retval;
    //int status;
    gpib_link_arg* arg = [[gpib_link_arg alloc] init];
    arg->cmd = IBQUERY_BOARD_RSV;
    
    //retval = ioctl( board->fileno, IBQUERY_BOARD_RSV, &status );
    retval = [board ioctl:arg];
    if( retval < 0 )
    {
        [self setIberr:EDVR];
        [self setIbcnt:errno];
        return retval;
    }
    
    return arg->nStatus;
}

-(int) query_pad:(gpib_link *) board : (UInt8 *) pad;
{
    int retval;
    //board_info_ioctl_t info;
    gpib_link_arg* arg = [[gpib_link_arg alloc] init];
    arg->cmd = IBBOARD_INFO;
    //retval = ioctl( board->fileno, IBBOARD_INFO, &info );
    retval = [board ioctl:arg];

    if( retval < 0 )
    {
        [self setIberr:EDVR];
        [self setIbcnt:errno];
        return retval;
    }
    
    *pad = arg->boardInfo.pad;
    return 0;
}

-(int) query_sad:(gpib_link *) board : (int *) sad;
{
    int retval;
    //board_info_ioctl_t info;
    gpib_link_arg* arg = [[gpib_link_arg alloc] init];
    arg->cmd = IBBOARD_INFO;
    //retval = ioctl( board->fileno, IBBOARD_INFO, &info );
    retval = [board ioctl:arg];

    if( retval < 0 )
    {
        [self setIberr:EDVR];
        [self setIbcnt:errno];
        return retval;
    }
    
    *sad = arg->boardInfo.sad;
    return 0;
}

-(int) query_no_7_bit_eos:(gpib_link *) board
{
    int retval;
    //board_info_ioctl_t info;
    gpib_link_arg* arg = [[gpib_link_arg alloc] init];
    arg->cmd = IBBOARD_INFO;
    //retval = ioctl(board->fileno, IBBOARD_INFO, &info);
    retval = [board ioctl:arg];

    if( retval < 0 )
    {
        [self setIberr:EDVR];
        [self setIbcnt:errno];
        return retval;
    }
    return arg->boardInfo.no_7_bit_eos;
}

-(int) my_ibbna:(ibConf_t *) conf : (UInt8) new_board_index
{
    ibConf_t *board_conf;
    int retval;
    int old_board_index;
    
    if( conf->is_interface )
    {
        [self setIberr:EARG];
        return -1;
    }
    retval = [self close_gpib_handle:conf];
    if( retval < 0 )
    {
        [self setIberr:EDVR];
        return -1;
    }
    
    board_conf = ibFindConfigs[new_board_index];
    if( board_conf->is_interface == 0 )
    {
        [self setIberr:EARG];
        return -1;
    }
    if( [self is_cic:[self interfaceBoard:board_conf]] == 0 )
    {
        [self setIberr:ECIC];
        return -1;
    }
    
    old_board_index = conf->settings.board;
    conf->settings.board = board_conf->settings.board;
    
    if( [self ibBoardOpen:conf->settings.board] < 0 )
    {
        [self setIberr:EDVR];
        return -1;
    }
    
    retval = [self open_gpib_handle:conf];
    if( retval < 0 )
    {
        [self setIberr:EDVR];
        return -1;
    }
    
    [self setIberr:old_board_index];
    return 0;
}

-(int) InternalDevClearList:(ibConf_t *) conf : (uint16_t *) addressList
{
    int i;
    gpib_link *board;
    UInt8 *cmd;
    size_t count;
    
    if( [self addressListIsValid:addressList] == NO )
    {
        return -1;
    }
    
    if( conf->is_interface == 0 )
    {
        [self setIberr:EDVR];
        return -1;
    }
    
    board = [self interfaceBoard:conf];
    
    if( [self is_cic:board] == NO)
    {
        [self setIberr:ECIC];
        return -1;
    }
    
    cmd = malloc( 16 + 2 * [self numAddresses:addressList] );
    if( cmd == NULL )
    {
        [self setIberr:EDVR];
        [self setIbcnt:ENOMEM];
        return -1;
    }
    
    i = 0;
    if( [self numAddresses:addressList]  )
    {
        i += [self create_send_setup:board : addressList : cmd];
        cmd[ i++ ] = SDC;
    }
    else
    {
        cmd[ i++ ] = DCL;
    }
    //XXX detect no listeners (EBUS) error
    count = [self my_ibcmd:conf : cmd : i];
    
    free( cmd );
    cmd = NULL;
    
    if(count != i)
    {
        return -1;
    }
    
    return 0;
}

-(int) set_spoll_timeout:(ibConf_t *) conf : (int) timeout
{
    if( timeout < TNONE || timeout > T1000s )
    {
        [self setIberr:EARG];
        return -1;
    }
    
    conf->settings.spoll_usec_timeout = [self timeout_to_usec:timeout];
    
    return 0;
}

-(int) set_ppoll_timeout:(ibConf_t *)conf : (int) timeout
{
    if( timeout < TNONE || timeout > T1000s )
    {
        [self setIberr:EARG];
        return -1;
    }
    
    conf->settings.ppoll_usec_timeout = [self ppoll_timeout_to_usec:timeout];
    
    return 0;
}

-(int) set_t1_delay:(gpib_link *)board : (int) delay
{
    //UInt8 nano_sec;
    gpib_link_arg* arg = [[gpib_link_arg alloc] init];
    arg->cmd = IB_T1_DELAY;
    int retval;
    
    switch( delay )
    {
        case T1_DELAY_2000ns:
            arg->nDelay = 2000;
            break;
        case T1_DELAY_500ns:
            arg->nDelay = 500;
            break;
        case T1_DELAY_350ns:
            arg->nDelay = 350;
            break;
        default:
            fprintf( stderr, "libmacosx_gpib: invalid T1 delay selection\n" );
            [self setIberr:EARG];
            return -1;
            break;
    }
    
    //retval = ioctl( board->fileno, IB_T1_DELAY, &nano_sec );
    retval = [board ioctl:arg];
    if( retval < 0 )
    {
        [self setIberr:EDVR];
        [self setIbcnt:errno];
        return -1;
    }
    
    return 0;
}

-(void) internal_ibeot:(ibConf_t *) conf : (BOOL) send_eoi
{
    if(send_eoi)
        conf->settings.send_eoi = 1;
    else
        conf->settings.send_eoi = 0;
}

-(int) internal_ibgts:(ibConf_t *) conf : (int) shadow_handshake
{
    gpib_link *board;
    int retval;
    
    board = [self interfaceBoard:conf];
    
    if( [self is_cic:board] == NO)
    {
        [self setIberr:ECIC];
        return -1;
    }
    
    //retval = ioctl( board->fileno, IBGTS, &shadow_handshake );
    retval = [board ibgts];
    if( retval < 0 )
    {
        [self setIberr:EDVR];
        [self setIbcnt:errno];
        return -1;
    }
    
    return 0;
}

-(int) internal_ibist:(ibConf_t *) conf : (BOOL) ist
{
    int retval;
    gpib_link *board;
    gpib_link_arg* arg = [[gpib_link_arg alloc] init];
    arg->cmd = IBPPC;
    
    if( conf->is_interface == 0 )
    {
        [self setIberr:EARG];
        return -1;
    }
    
    board = [self interfaceBoard:conf];

    retval = [self query_ist:board];
    if( retval < 0 ) return retval;
    [self setIberr:retval];	// set iberr to old ist value
    
    arg->nConfig = 0;
    arg->bSetIst = NO;
    arg->bClearIst = NO;
    if( ist )
        arg->bSetIst = YES;
    else
        arg->bClearIst = YES;
    //retval = ioctl( interfaceBoard( conf )->fileno, IBPPC, &cmd );
    retval = [board ioctl:arg];
    if( retval < 0 )
    {
        [self setIberr:EDVR];
        [self setIbcnt:errno];
        return -1;
    }
    
    return 0;
}

-(int) internal_iblines:(ibConf_t *) conf : (short *) line_status
{
    int retval;
    gpib_link *board;
    gpib_link_arg* arg = [[gpib_link_arg alloc] init];
    arg->cmd = IBLINES;
    
    if( conf->is_interface == NO )
    {
        [self setIberr:EARG];
        return -1;
    }
    
    board = [self interfaceBoard:conf];
    
    //retval = ioctl( board->fileno, IBLINES, line_status );
    retval = [board ioctl:arg];
    *line_status = arg->nLines;
    if( retval < 0 )
    {
        switch( errno )
        {
            default:
                [self setIbcnt:errno];
                [self setIberr:EDVR];
                break;
        }
        return -1;
    }
    return 0;
}

-(int) internal_ibppc:(ibConf_t *) conf : (int) v
{
    static const int ppc_mask = 0xe0;
    int retval;
    
    if( v && ( v & ppc_mask ) != PPE )
    {
        fprintf( stderr, "libmacosx_gpib: illegal parallel poll configuration\n" );
        [self setIberr:EARG];
        return -1;
    }
    
    if( !v || (v & PPC_DISABLE) )
        v = PPD;
    
    if( conf->is_interface )
    {
        retval = [self board_ppc:conf : v];
        if( retval < 0 )
            return retval;
    }else
    {
        retval = [self device_ppc:conf : v];
        if( retval < 0 ) return retval;
    }
    
    [self setIberr:conf->settings.ppoll_config];
    conf->settings.ppoll_config = v;
    
    return 0;
}

-(int) device_ppc:(ibConf_t *) conf : (int) ppc_configuration
{
    uint16_t addressList[ 2 ];
    
    addressList[ 0 ] = [self packAddress:conf->settings.pad : conf->settings.sad];
    addressList [ 1 ] = NOADDR;
    
    return [self ppoll_configure_device:conf : addressList : ppc_configuration];
}

-(int) board_ppc:(ibConf_t *) conf : (int) ppc_configuration
{
    gpib_link *board;
    int retval;
    gpib_link_arg* arg = [[gpib_link_arg alloc] init];
    arg->cmd = IBPPC;
    
    board = [self interfaceBoard:conf];
    
    if( conf->settings.local_ppc == 0 )
    {
        [self setIberr:ECAP];
        return -1;
    }
    
    retval = [self query_ppc:board];
    if( retval < 0 ) return retval;
    conf->settings.ppoll_config = retval;	// store old value
    
    arg->nConfig = ppc_configuration;
    arg->bSetIst = NO;
    arg->bClearIst = NO;
    //retval = ioctl( board->fileno, IBPPC, &cmd );
    retval = [board ioctl:arg];
    if( retval < 0 )
    {
        [self setIberr:EDVR];
        [self setIbcnt:errno];
        return -1;
    }
    
    return 0;
}

-(int) listenerFound:(ibConf_t *) conf :(uint16_t *) addressList
{
    UInt8 *cmd;
    int i, j;
    short line_status;
    int retval;
    
    if( addressList == NULL )
        return 0;
    if( [self addressListIsValid:addressList] == NO )
        return -1;
    
    cmd = malloc( 16 + 2 * [self numAddresses:addressList] );
    if( cmd == NULL )
    {
        [self setIberr:EDVR];
        [self setIbcnt:ENOMEM];
        return -1;
    }
    
    j = 0;
    cmd[ j++ ] = MTA( conf->settings.pad ); /* address the gpib
                                             card as talker is required on Meas. Comp. PCI-GPIB-1M card */
    cmd[ j++ ] = UNL;
    for( i = 0; i < [self numAddresses:addressList]; i++ )
    {
        int pad, sad;
        
        pad = [self extractPAD:addressList[ i ]];
        sad = [self extractSAD:addressList[ i ]];
        cmd[ j++ ] = MLA( pad );
        if( sad >= 0 )
            cmd[ j++ ] = MSA( sad );
    }
    retval = (int)[self my_ibcmd:conf : cmd : j];
    
    free( cmd );
    cmd = NULL;
    
    if( retval < 0 )
        return retval;
    
    retval = [self internal_ibgts:conf : NO];
    if( retval < 0 ) return -1;
    
    usleep( 1500 );
    
    retval = [self internal_iblines:conf : &line_status];
    if( retval < 0 ) return retval;
    
    if( ( line_status & ValidNDAC ) &&
       ( line_status & BusNDAC ) )
    {
        return 1;
    }
    
    return 0;
}

-(int) secondaryListenerFound:(ibConf_t *) conf : (UInt8) pad
{
    uint16_t testAddress[ 32 ];
    int j;
    
    for( j = 0; j <= gpib_addr_max; j++ )
        testAddress[ j ] = [self packAddress:pad : j];
    testAddress[ j ] = NOADDR;
    return [self listenerFound:conf : testAddress];
}

-(int) reinit_descriptor:(ibConf_t *) conf
{
    int retval;
    
    retval = [self internal_ibpad:conf : conf->defaults.pad];
    if( retval < 0 ) return retval;
    retval = [self internal_ibsad:conf : conf->defaults.sad];
    if( retval < 0 ) return retval;
    retval = [self my_ibbna:conf : conf->defaults.board];
    if( retval < 0 ) return retval;
    conf->settings.usec_timeout = conf->defaults.usec_timeout;
    conf->settings.spoll_usec_timeout = conf->defaults.usec_timeout;
    conf->settings.ppoll_usec_timeout = conf->defaults.usec_timeout;
    conf->settings.eos = conf->defaults.eos;
    conf->settings.eos_flags = conf->defaults.eos_flags;
    conf->settings.eos = conf->defaults.eos;
    conf->settings.ppoll_config = conf->defaults.ppoll_config;
    [self internal_ibeot:conf : conf->defaults.send_eoi];
    conf->settings.local_lockout = conf->defaults.local_lockout;
    conf->settings.local_ppc = conf->defaults.local_ppc;
    conf->settings.readdr = conf->defaults.readdr;
    return 0;
}

-(int) ThreadIbsta
{
    int thread_ibsta;
    [self globals_alloc];
    thread_ibsta = [[thread_key valueForKey:@"ibsta_key"] intValue];
    return thread_ibsta;
}

-(int) ThreadIberr
{
    int thread_iberr;
    [self globals_alloc];
    thread_iberr = [[thread_key valueForKey:@"iberr_key"] intValue];
    return thread_iberr;
}

-(int) ThreadIbcnt
{
    int thread_ibcntl;
    [self globals_alloc];
    thread_ibcntl = [[thread_key valueForKey:@"ibcntl_key"] intValue];
    return thread_ibcntl;
}

-(int) internal_ibpad:(ibConf_t *) conf : (UInt8) address
{
    int retval;
    
    if( address > 30 )
    {
        [self setIberr:EARG];
        fprintf( stderr, "libmacosx_gpib: invalid gpib address\n" );
        return -1;
    }
    
    retval = [self gpibi_change_address:conf : address : conf->settings.sad];
    if( retval < 0 )
    {
        fprintf( stderr, "libmacosx_gpib: failed to change gpib address\n" );
        return -1;
    }
    
    return 0;
}

-(int) my_pass_control:(ibConf_t *) conf : (UInt8) pad : (int) sad
{
    UInt8 cmd;
    int retval;
    
    [self InternalReceiveSetup:conf : [self packAddress:pad : sad]];
    
    cmd = TCT;
    retval = (int)[self my_ibcmd:conf : &cmd : 1];
    if( retval < 0 )
        return retval;
    
    retval = [self internal_ibgts:conf : 0];
    
    return retval;
}

-(int) ppoll_configure_device:(ibConf_t *) conf : (uint16_t *) addressList : (int) ppc_configuration
{
    UInt8 *cmd;
    int i;
    int retval;
    
    if( [self is_cic:[self interfaceBoard:conf]] == NO )
    {
        [self setIberr:ECIC];
        return -1;
    }
    
    cmd = malloc( 16 + 2 * [self numAddresses:addressList] );
    if( cmd == NULL )
    {
        [self setIberr:EDVR];
        [self setIbcnt:ENOMEM];
        return -1;
    }
    
    i = [self create_send_setup: [self interfaceBoard:conf] : addressList : cmd];
    
    cmd[ i++ ] = PPC;
    cmd[ i++ ] = ppc_configuration;
    
    retval = (int)[self my_ibcmd:conf : cmd : i];
    
    free( cmd );
    cmd = NULL;
    
    if( retval < 0 )
    {
        return -1;
    }
    
    return 0;
}

-(ssize_t) my_ibrd:(ibConf_t *) conf : (UInt8 *) buffer : (size_t) count : (size_t *) bytes_read
{
    *bytes_read = 0;
    // set eos mode
    [self iblcleos:conf];
    if( conf->is_interface == NO )
    {
        // set up addressing
        if( [self InternalReceiveSetup:conf : [self packAddress:conf->settings.pad : conf->settings.sad]] < 0 )
            return -1;
    }
    return [self read_data:conf : buffer : count : bytes_read];
}

-(ssize_t) read_data:(ibConf_t *) conf : (UInt8 *) buffer : (size_t) count : (size_t *) bytes_read
{
    gpib_link *board;
    int retval;
    gpib_link_arg* arg = [[gpib_link_arg alloc] init];
    arg->cmd = IBRD;
    
    board = [self interfaceBoard:conf];
    /*
    assert(sizeof(buffer) <= sizeof(arg->readWrite.buffer_ptr));
    arg->readWrite.buffer_ptr = buffer;
    arg->readWrite.requested_transfer_count = count;
    arg->readWrite.completed_transfer_count = 0;
    arg->readWrite.handle = conf->handle;
    arg->readWrite.end = 0;*/
    arg->read_ioctl = [[NSMutableDictionary alloc] initWithObjectsAndKeys:
     [NSNumber numberWithInteger:conf->handle],@"handle",
     [[NSMutableData alloc] init],@"buffer",
     [NSNumber numberWithInteger:count],@"requested_transfer_count",
     [NSNumber numberWithInteger:0],@"completed_transfer_count",
     [NSNumber numberWithBool:NO],@"end",
     nil];
    
    [self set_timeout:board : conf->settings.usec_timeout];
    conf->end = 0;
    
    //retval = ioctl( board->fileno, IBRD, &read_cmd );
    retval = [board ioctl:arg];
    if( retval < 0 )
    {
        switch( errno )
        {
            case ETIMEDOUT:
                conf->timed_out = 1;
                [self setIberr:EABO];
                break;
            default:
                [self setIberr:EDVR];
                [self setIbcnt:errno];
                break;
        }
    }
    
    //if( arg->readWrite.end ) conf->end = YES;
    conf->end = [[arg->read_ioctl valueForKey:@"end"] boolValue];
    //*bytes_read = arg->readWrite.completed_transfer_count;
    *bytes_read = [[arg->read_ioctl valueForKey:@"completed_transfer_count"] intValue];
    [[arg->read_ioctl valueForKey:@"buffer"] getBytes:buffer length:*bytes_read];
    
    if(*bytes_read < count)
        buffer[*bytes_read] = '\0';
    
    return retval;
}

// sets up bus to receive data from device with address pad/sad
-(int) InternalReceiveSetup:(ibConf_t *) conf : (uint16_t) address
{
    gpib_link *board;
    UInt8 cmdString[8];
    UInt8 i = 0;
    UInt8 pad, board_pad;
    int sad, board_sad;
    
    if( [self addressIsValid:address] == NO ||
       address == NOADDR )
    {
        [self setIberr:EARG];
        return -1;
    }
    board = [self interfaceBoard:conf];
    
    if( [self query_pad:board : &board_pad] < 0 ) return -1;
    if( [self query_sad:board : &board_sad] < 0 ) return -1;
    
    pad = [self extractPAD:address];
    sad = [self extractSAD:address];
    
    cmdString[ i++ ] = UNL;
    
    cmdString[ i++ ] = MLA( board_pad );	/* controller's listen address */
    if ( board_sad >= 0 )
        cmdString[ i++ ] = MSA( board_sad );
    cmdString[ i++ ] = MTA( pad );
    if( sad >= 0 )
        cmdString[ i++ ] = MSA( sad );
    
    if ( [self my_ibcmd:conf : cmdString : i] < 0)
    {
        fprintf(stderr, "%s: command failed\n", __FUNCTION__ );
        return -1;
    }
    
    return 0;
}

-(int) internal_ibrpp:(ibConf_t *) conf : (char *) result
{
    gpib_link *board;
    int retval=0;
    gpib_link_arg* arg = [[gpib_link_arg alloc] init];
    arg->cmd = IBRPP;
    
    board = [self interfaceBoard:conf];
    
    if( [self is_cic:board] == NO )
    {
        [self setIberr:ECIC];
        return -1;
    }
    
    [self set_timeout:board : conf->settings.ppoll_usec_timeout];

    //retval = ioctl( board->fileno, IBRPP, &poll_byte );
    retval = [board ioctl:arg];

    if( retval < 0 )
    {
        switch( errno )
        {
            case ETIMEDOUT:
                conf->timed_out = 1;
                break;
            default:
                [self setIberr:EDVR];
                [self setIbcnt:errno];
                break;
        }
        return -1;
    }
    
    *result = (char)arg->nPollByte;
    
    return 0;
}

-(int) internal_ibrsc:(ibConf_t *) conf : (int) request_control
{
    int retval;
    
    if( conf->is_interface == 0 )
    {
        [self setIberr:EARG];
        return -1;
    }
    
    retval = [self request_system_control: [self interfaceBoard:conf] : request_control];
    if( retval < 0 )
        return retval;
    
    return 0;
}

-(int) request_system_control:(gpib_link *) board : (BOOL) request_control
{
    int retval;
    gpib_link_arg* arg = [[gpib_link_arg alloc] init];
    arg->cmd = IBRSC;
    arg->bRequestControl = request_control;
    
    //retval = ioctl( board->fileno, IBRSC, &rsc_cmd );
    retval = [board ioctl:arg];
    if( retval < 0 )
    {
        fprintf( stderr, "libmacosx_gpib: IBRSC ioctl failed\n" );
        [self setIberr:EDVR];
        [self setIbcnt:errno];
        return retval;
    }
    return 0;
}

-(int) serial_poll:(gpib_link *) board : (UInt8) pad : (SInt8) sad : (UInt32) usec_timeout : (UInt8 *) result
{
    int retval;
    gpib_link_arg* arg = [[gpib_link_arg alloc] init];
    arg->cmd = IBRSP;
    arg->pad = pad;
    arg->sad = sad;
    arg->nUsecDuration = usec_timeout;
    
    [self set_timeout:board : usec_timeout];
    
    retval = [board ioctl:arg];
    
    if(retval < 0)
    {
        switch( errno )
        {
            case ETIMEDOUT:
                [self setIberr:EABO];
                break;
            case EPIPE:
                [self setIberr:ESTB];
                break;
            default:
                [self setIberr:EDVR];
                [self setIbcnt:errno];
                break;
        }
        return -1;
    }
    
    *result = arg->nStatusByte;
    
    return 0;
}

-(int) internal_ibrsv:(ibConf_t *) conf : (UInt8) status_byte
{
    gpib_link *board;
    int retval;
    gpib_link_arg* arg = [[gpib_link_arg alloc] init];
    arg->cmd = IBRSV;
    arg->nStatusByte = status_byte;
    
    if( conf->is_interface == 0 )
    {
        [self setIberr:EARG];
        return -1;
    }
    
    board = [self interfaceBoard:conf];
    
    //retval = ioctl( board->fileno, IBRSV, &status_byte );
    retval = [board ioctl:arg];
    if( retval < 0 )
    {
        return retval;
    }
    
    return 0;
}

-(int) internal_ibsad:(ibConf_t *) conf : (int) address
{
    int sad = address - sad_offset;
    int retval;
    
    if( sad > 30 )
    {
        [self setIberr:EARG];
        return -1;
    }
    
    retval = [self gpibi_change_address:conf : address : conf->settings.sad];
    if( retval < 0 )
    {
        fprintf( stderr, "libmacosx_gpib: failed to change gpib address\n" );
        return -1;
    }
    return 0;
}

-(int) assert_ifc:(gpib_link *) board : (UInt8) usec
{
    int retval;
    gpib_link_arg* arg = [[gpib_link_arg alloc] init];
    arg->cmd = IBSIC;
    arg->nUsecDuration = usec;
    //retval = ioctl( board->fileno, IBSIC, &usec_duration );
    retval = [board ioctl:arg];
    if( retval < 0 )
    {
        [self setIberr:EDVR];
        [self setIbcnt:errno];
    }
    return retval;
}

-(int) internal_ibsic:(ibConf_t *) conf
{
    gpib_link *board;
    
    if( conf->is_interface == 0 )
    {
        [self setIberr:EARG];
        return -1;
    }
    
    board = [self interfaceBoard:conf];
    
    if( [self is_system_controller:board] == 0 )
    {
        [self setIberr:ESAC];
        return -1;
    }
    
    return [self assert_ifc:board : 100];
}

-(int) remote_enable:(gpib_link *) board : (BOOL) enable
{
    int retval;
    gpib_link_arg* arg = [[gpib_link_arg alloc] init];
    arg->cmd = IBSRE;
    arg->bEnable = enable;
    
    if( [self is_system_controller:board] == 0 )
    {
        [self setIberr:ESAC];
        return -1;
    }
    
    //retval = ioctl( board->fileno, IBSRE, &enable );
    retval = [board ioctl:arg];
    if( retval < 0 )
    {
        // XXX other error types?
        [self setIberr:EDVR];
        [self setIbcnt:errno];
        return retval;
    }
    
    return 0;
}

-(int) internal_ibsre:(ibConf_t *) conf : (BOOL) enable
{
    gpib_link *board;
    int retval;
    
    board = [self interfaceBoard:conf];
    
    if( conf->is_interface == 0 )
    {
        [self setIberr:EARG];
        return -1;
    }
    
    retval = [self remote_enable:board : enable];
    if( retval < 0 )
        return retval;
    
    return 0;
}

-(int) InternalEnableRemote:(ibConf_t *) conf : (uint16_t *) addressList
{
    int i;
    gpib_link *board;
    UInt8 *cmd;
    int count;
    int retval;
    
    if( [self addressListIsValid:addressList] == NO )
        return -1;
    
    if( conf->is_interface == 0 )
    {
        [self setIberr:EDVR];
        return -1;
    }
    
    board = [self interfaceBoard:conf];
    
    if( [self is_cic:board] == NO)
    {
        [self setIberr:ECIC];
        return -1;
    }
    
    retval = [self remote_enable:board : YES];
    if( retval < 0 ) return -1;
    
    if( [self numAddresses:addressList] == 0 )
        return 0;
    
    cmd = malloc( 16 + 2 * [self numAddresses:addressList] );
    if( cmd == NULL )
    {
        [self setIberr:EDVR];
        [self setIbcnt:ENOMEM];
        return -1;
    }
    
    i = [self create_send_setup:board : addressList : cmd];
    
    //XXX detect no listeners (EBUS) error
    count = (int)[self my_ibcmd:conf : cmd : i];
    
    free( cmd );
    cmd = NULL;
    
    if( count != i )
        return -1;
    
    return 0;
}

-(void) cancelThread:(NSThread*) thread
{
    [thread cancel];
}

-(int) internal_ibstop:(ibConf_t *) conf
{    
    pthread_mutex_lock( &conf->async->lock );
    if( conf->async->in_progress == NO )
    {
        pthread_mutex_unlock( &conf->async->lock );
        return 0;
    }
    
    if(conf->async->thread == nil)
        return 0;
    
    if([conf->async->thread isExecuting] == NO)
        return 0;
    
    [self performSelector:@selector(cancelThread:) onThread:conf->async->thread withObject:conf->async->thread waitUntilDone:YES];
    
    if( [conf->async->thread isCancelled] )
    {
        conf->async->thread = nil;
        conf->async->in_progress = NO;
        pthread_mutex_unlock( &conf->async->lock );
        return 0;
    }
    pthread_mutex_unlock( &conf->async->lock );
    [self setIberr:EABO];
    
    return 1;
}

-(int) internal_ibtmo:(ibConf_t *) conf : (int) timeout
{
    if( timeout < TNONE || timeout > T1000s )
    {
        [self setIberr:EARG];
        return -1;
    }
    
    conf->settings.usec_timeout = [self timeout_to_usec:timeout];
    
    return 0;
}

-(int) my_trigger:(ibConf_t *)conf : (uint16_t*) addressList
{
    int i, retval;
    UInt8 *cmd;
    
    if( [self addressListIsValid:addressList] == NO )
    {
        [self setIberr:EARG];
        return -1;
    }
    
    cmd = malloc( 16 + 2 * [self numAddresses:addressList]);
    if( cmd == NULL )
    {
        [self setIberr:EDVR];
        [self setIbcnt:ENOMEM];
        return -1;
    }
    
    i = [self create_send_setup: [self interfaceBoard:conf] : addressList : cmd];
    cmd[ i++ ] = GET;
    
    retval = (int)[self my_ibcmd:conf : cmd : i];
    
    free( cmd );
    cmd = NULL;
    
    if( retval != i )
    {
        return -1;
    }
    
    return 0;
}

-(void) fixup_status_bits:(ibConf_t *)conf : (int *) status
{
    const int board_wait_mask = board_status_mask & ~ERR;
    const int device_wait_mask = device_status_mask & ~ERR;
    
    if( conf->is_interface == 0 )
    {
        *status &= device_wait_mask;
    }else
    {
        *status &= board_wait_mask;
        if( [[self interfaceBoard:conf] use_event_queue] )
        {
            *status &= ~DTAS & ~DCAS;
        }else
        {
            *status &= ~EVENT;
        }
    }
}

-(int) my_wait:(ibConf_t *)conf : (int) wait_mask : (int) clear_mask : (int) set_mask : (int *) status
{
    gpib_link *board;
    int retval;
    gpib_link_arg* arg = [[gpib_link_arg alloc] init];
    SInt32 arg_wait_mask = wait_mask;
    SInt32 arg_wait_ibsta;
    //SInt16 pad, sad;
    
    board = [self interfaceBoard:conf];
    
    if( conf->is_interface == NO && [self is_cic:board] == NO)
    {
        [self setIberr:ECIC];
        return -1;
    }

    /*arg->wait.handle = conf->handle;
    arg->wait.usec_timeout = conf->settings.usec_timeout;
    arg->wait.wait_mask = wait_mask;
    arg->wait.clear_mask = clear_mask;
    arg->wait.set_mask = set_mask;
    arg->wait.ibsta = 0;*/
    arg->cmd = IBWAIT;
    //[self fixup_status_bits:conf : &arg->wait.wait_mask];
    [self fixup_status_bits:conf : &arg_wait_mask];/*
    if( conf->is_interface == 0 )
    {
        //arg->wait.pad = conf->settings.pad;
        //arg->wait.sad = conf->settings.sad;
        pad = conf->settings.pad;
        sad = conf->settings.sad;
    }else
    {
        //arg->wait.pad = NOADDR;
        //arg->wait.sad = NOADDR;
        pad = NOADDR;
        sad = NOADDR;
        //XXX additionally, clear wait mask depending on event queue enabled, etc
    }*/
    
    //if( wait_mask != arg->wait.wait_mask )
    if( wait_mask != arg_wait_mask )
    {
        [self setIberr:EARG];
        return -1;
    }

    arg->read_ioctl = [[NSMutableDictionary alloc] initWithObjectsAndKeys:
                       [NSNumber numberWithInteger:conf->handle],@"handle",
                       [NSNumber numberWithLong:conf->settings.usec_timeout],@"usec_timeout",
                       [NSNumber numberWithInteger:arg_wait_mask],@"wait_mask",
                       [NSNumber numberWithInteger:clear_mask],@"clear_mask",
                       [NSNumber numberWithInteger:set_mask],@"set_mask",
                       [NSNumber numberWithInteger:0],@"ibsta",
                       //[NSNumber numberWithInteger:pad],@"pad",
                       //[NSNumber numberWithInteger:sad],@"sad",
                       [NSNumber numberWithInteger:IBWAIT],@"cmd",
                       nil];
    
    //retval = ioctl(board->fileno, IBWAIT, &cmd);
    retval = [board ioctl:arg];
    if( retval < 0 )
    {
        [self setIberr:EDVR];
        [self setIbcnt:errno];
        return -1;
    }
    arg_wait_ibsta = [[arg->read_ioctl valueForKey:@"ibsta"] intValue];
    //[self fixup_status_bits:conf : &arg->wait.ibsta];
    [self fixup_status_bits:conf : &arg_wait_ibsta];
    if( conf->end ) //XXX
        //arg->wait.ibsta |= END;
        arg_wait_ibsta |= END;
    //[self setIbsta:arg->wait.ibsta];
    [self setIbsta: arg_wait_ibsta];
    //*status = arg->wait.ibsta;
    *status = arg_wait_ibsta;
    return 0;
}

-(int) InternalSendList:(ibConf_t *) conf : (uint16_t *) addressList : (void *) buffer : (long) count : (int) eotmode
{
    gpib_link *board;
    int retval;
    
    if( [self addressListIsValid:addressList] == NO ||
       [self numAddresses:addressList] == 0 )
    {
        [self setIberr:EARG];
        return -1;
    }
    
    if( conf->is_interface == 0 )
    {
        [self setIberr:EARG];
        return -1;
    }
    
    board = [self interfaceBoard:conf];
    
    if( [self is_cic:board] == NO )
    {
        [self setIberr:ECIC];
        return -1;
    }
    
    retval = [self InternalSendSetup:conf : addressList];
    if( retval < 0 ) return retval;
    
    retval = [self InternalSendDataBytes: conf : buffer : count : eotmode];
    if( retval < 0 ) return retval;
    
    return 0;
}

-(int) InternalSendDataBytes:(ibConf_t *) conf : (void *) buffer : (size_t) count : (int) eotmode
{
    int retval;
    size_t num_bytes;
    size_t bytes_written = 0;
    
    if( conf->is_interface == 0 )
    {
        [self setIberr:EARG];
        return -1;
    }
    
    switch( eotmode )
    {
        case DABend:
        case NLend:
        case NULLend:
            break;
        default:
            [self setIberr:EARG];
            return -1;
            break;
    }
    
    retval = [self send_data:conf : buffer : count : eotmode == DABend : &num_bytes];
    bytes_written += num_bytes;
    if( retval < 0 )
    {
        [self setIbcnt:bytes_written];
        return retval;
    }
    if( eotmode == NLend )
    {
        retval = [self send_data:conf : "\n" : 1 : 1 : &num_bytes];
        bytes_written += num_bytes;
        if( retval < 0 )
        {
            [self setIbcnt:bytes_written];
            return retval;
        }
    }
    [self setIbcnt:bytes_written];
    return 0;
}

-(int) my_ibwrtf:(ibConf_t *) conf : (char *) file_path : (size_t *) bytes_written
{
    gpib_link *board;
    long count;
    size_t block_size;
    int retval;
    FILE *data_file;
    struct stat file_stats;
    UInt8 buffer[ 0x4000 ];
    
    *bytes_written = 0;
    board = [self interfaceBoard:conf];
    
    data_file = fopen( file_path, "r" );
    if( data_file == NULL )
    {
        [self setIberr:EFSO];
        [self setIbcnt:errno];
        return -1;
    }
    
    retval = fstat( fileno( data_file ), &file_stats );
    if( retval < 0 )
    {
        [self setIberr:EFSO];
        [self setIbcnt:errno];
        return -1;
    }
    
    count = file_stats.st_size;
    
    if( conf->is_interface == 0 )
    {
        // set up addressing
        if( [self send_setup:conf] < 0 )
        {
            return -1;
        }
    }
    
    [self set_timeout:board : conf->settings.usec_timeout];
    
    while( count )
    {
        size_t fread_count;
        int send_eoi;
        size_t buffer_offset = 0;
        
        fread_count = fread( buffer, 1, sizeof( buffer ), data_file );
        if( fread_count == 0 )
        {
            [self setIberr:EFSO];
            [self setIbcnt:errno];
            return -1;
        }
        while(buffer_offset < fread_count)
        {
            send_eoi = conf->settings.send_eoi && (count == fread_count - buffer_offset);
            retval = [self send_data_smart_eoi:conf : buffer + buffer_offset : fread_count - buffer_offset : send_eoi : &block_size];
            count -= block_size;
            buffer_offset += block_size;
            *bytes_written += block_size;
            if(retval < 0)
            {
                return -1;
            }
        }
    }
    return 0;
}

-(int) send_data_smart_eoi:(ibConf_t *) conf : (void *) buffer : (size_t) count : (int) force_eoi : (size_t *) bytes_written
{
    int eoi_on_eos;
    int eos_found = 0;
    int send_eoi;
    unsigned long block_size;
    int retval;
    
    eoi_on_eos = conf->settings.eos_flags & XEOS;
    
    block_size = count;
    
    if( eoi_on_eos )
    {
        retval = [self find_eos:buffer : count : conf->settings.eos : conf->settings.eos_flags];
        if( retval < 0 ) eos_found = 0;
        else
        {
            block_size = retval;
            eos_found = 1;
        }
    }
    
    send_eoi = force_eoi || ( eoi_on_eos && eos_found );
    if([self send_data:conf : buffer : block_size : send_eoi : bytes_written] < 0)
    {
        return -1;
    }
    return 0;
}

-(int) find_eos:(UInt8 *) buffer : (size_t) length : (int) eos : (int) eos_flags
{
    UInt8 i;
    UInt8 compare_mask;
    
    if( eos_flags & BIN ) compare_mask = 0xff;
    else compare_mask = 0x7f;
    
    for( i = 0; i < length; i++ )
    {
        if( ( buffer[i] & compare_mask ) == ( eos & compare_mask ) )
            return i;
    }
    
    return -1;
}

-(int) send_data:(ibConf_t *)conf : (void *) buffer : (size_t) count : (BOOL) send_eoi : (size_t *) bytes_written
{
    gpib_link *board;
    gpib_link_arg* arg = [[gpib_link_arg alloc] init];
    arg->cmd = IBWRT;
    int retval;
    
    board = [self interfaceBoard:conf];
    
    [self set_timeout:board : conf->settings.usec_timeout];
    
    /*assert(sizeof(buffer) <= sizeof(arg->readWrite.buffer_ptr));
    arg->readWrite.buffer_ptr = buffer;
    arg->readWrite.requested_transfer_count = count;
    arg->readWrite.completed_transfer_count = 0;
    arg->readWrite.end = send_eoi;
    arg->readWrite.handle = conf->handle;*/
    arg->read_ioctl = [[NSMutableDictionary alloc] initWithObjectsAndKeys:
                       [NSNumber numberWithInteger:conf->handle],@"handle",
                       [[NSMutableData alloc] initWithBytes:buffer length:count],@"buffer",
                       [NSNumber numberWithInteger:count],@"requested_transfer_count",
                       [NSNumber numberWithInteger:0],@"completed_transfer_count",
                       [NSNumber numberWithBool:send_eoi],@"send_eoi",
                       nil];
    
    //retval = ioctl( board->fileno, IBWRT, &write_cmd);
    retval = [board ioctl:arg];
    if(retval < 0)
    {
        switch( errno )
        {
            case ETIMEDOUT:
                conf->timed_out = 1;
                [self setIberr:EABO];
                break;
            case EINTR:
                [self setIberr:EABO];
                break;
            case EIO:
                [self setIberr:ENOL];
                break;
            case EFAULT:
                //fall-through
            default:
                [self setIberr:EDVR];
                [self setIbcnt:errno];
                break;
        }
    }
    //*bytes_written = arg->readWrite.completed_transfer_count;
    *bytes_written = [[arg->read_ioctl valueForKey:@"completed_transfer_count"] intValue];
    conf->end = send_eoi && (*bytes_written == count);
    if(retval < 0) return retval;
    return 0;
}

-(int) my_ibwrt:(ibConf_t *) conf : (UInt8 *) buffer : (size_t) count : (size_t *) bytes_written
{
    gpib_link *board;
    size_t block_size;
    int retval;
    
    *bytes_written = 0;
    board = [self interfaceBoard:conf];
    
    [self set_timeout:board : conf->settings.usec_timeout];
    
    if( conf->is_interface == 0 )
    {
        // set up addressing
        if( [self send_setup:conf] < 0 )
        {
            return -1;
        }
    }
    
    while( count )
    {
        retval = [self send_data_smart_eoi:conf : buffer : count : conf->settings.send_eoi : &block_size];
        *bytes_written += block_size;
        if(retval < 0)
        {
            return -1;
        }
        count -= block_size;
        buffer += block_size;
    }
    return 0;
}

-(int) extractPAD:(uint16_t) address
{
    int pad = address & 0xff;
    
    if( address == NOADDR ) return ADDR_INVALID;
    
    if( pad < 0 || pad > gpib_addr_max ) return ADDR_INVALID;
    
    return pad;
}

-(int) extractSAD:(uint16_t) address
{
    int sad = ( address >> 8 ) & 0xff;
    
    if( address == NOADDR ) return ADDR_INVALID;
    
    if( sad == NO_SAD ) return SAD_DISABLED;
    
    if( ( sad & 0x60 ) == 0 ) return ADDR_INVALID;
    
    sad &= ~0x60;
    
    if( sad < 0 || sad > gpib_addr_max ) return ADDR_INVALID;
    
    return sad;
}

-(BOOL) addressIsValid:(uint16_t) address
{
    if( address == NOADDR ) return 1;
    
    if( [self extractPAD:address] == ADDR_INVALID ||
       [self extractSAD:address] == ADDR_INVALID )
    {
        [self setIberr:EARG];
        return 0;
    }
    
    return 1;
}

-(BOOL) addressListIsValid:(uint16_t *) addressList;
{
    int i;
    
    if( addressList == NULL ) return 1;
    
    for( i = 0; addressList[ i ] != NOADDR; i++ )
    {
        if( [self addressIsValid:addressList[ i ]] == NO )
        {
            [self setIbcnt:i];
            return 0;
        }
    }
    
    return 1;
}

-(int) set_timeout:(gpib_link *) board : (UInt32) usec_timeout
{
    gpib_link_arg* arg = [[gpib_link_arg alloc] init];
    arg->cmd = IBTMO;
    arg->nUsecDuration = usec_timeout;
    //return ioctl( board->fileno, IBTMO, &usec_timeout);
    return [board ioctl:arg];
}

-(UInt8) numAddresses:(uint16_t *) addressList
{
    UInt8 count;
    
    if( addressList == NULL )
        return 0;
    
    count = 0;
    while( addressList[ count ] != NOADDR )
    {
        count++;
    }
    
    return count;
}

-(BOOL) is_cic:(gpib_link *) board
{
    int retval;
    gpib_link_arg* arg = [[gpib_link_arg alloc] init];
    /*arg->wait.usec_timeout = 0;
    arg->wait.wait_mask = 0;
    arg->wait.clear_mask = 0;
    arg->wait.set_mask = 0;
    arg->wait.pad = NOADDR;
    arg->wait.sad = NOADDR;
    arg->wait.handle = 0;
    arg->wait.ibsta = 0;*/
    arg->cmd = IBWAIT;

    arg->read_ioctl = [[NSMutableDictionary alloc] initWithObjectsAndKeys:
                       [NSNumber numberWithInteger:0],@"handle",
                       [NSNumber numberWithLong:0],@"usec_timeout",
                       [NSNumber numberWithInteger:0],@"wait_mask",
                       [NSNumber numberWithInteger:0],@"clear_mask",
                       [NSNumber numberWithInteger:0],@"set_mask",
                       [NSNumber numberWithInteger:0],@"ibsta",
                       //[NSNumber numberWithInteger:NOADDR],@"pad",
                       //[NSNumber numberWithInteger:NOADDR],@"sad",
                       [NSNumber numberWithInteger:IBWAIT],@"cmd",
                       nil];
    //retval = ioctl( board->fileno, IBWAIT, &cmd );
    retval = [board ioctl:arg];
    if( retval < 0 )
    {
        [self setIberr:EDVR];
        [self setIbcnt:errno];
        fprintf( stderr, "libmacosx_gpib: error in is_cic()!\n");
        return -1;
    }
    
    //if( arg->wait.ibsta & CIC )
    if([[arg->read_ioctl valueForKey:@"ibsta"] intValue] & CIC)
        return YES;
    
    return NO;
}

-(int) is_system_controller:(gpib_link *) board
{
    int retval;
    //board_info_ioctl_t info;
    gpib_link_arg* arg = [[gpib_link_arg alloc] init];
    arg->cmd = IBBOARD_INFO;
    
    //retval = ioctl( board->fileno, IBBOARD_INFO, &info );
    retval = [board ioctl:arg];
    if( retval < 0 )
    {
        fprintf( stderr, "libmacosx_gpib: error in is_system_controller()!\n");
        return retval;
    }
    
    return arg->boardInfo.is_system_controller;
}

-(int) InternalRcvRespMsg:(ibConf_t *) conf : (void *) buffer : (long) count : (int) termination
{
    gpib_link *board;
    int retval;
    int use_eos;
    size_t bytes_read;
    
    if( conf->is_interface == 0 )
    {
        [self setIberr:EARG];
        return -1;
    }
    
    board = [self interfaceBoard:conf];
    
    if( [self is_cic:board] == NO )
    {
        [self setIberr:ECIC];
        return -1;
    }
    
    if( termination != ( termination & 0xff ) &&
       termination != STOPend )
    {
        [self setIberr:EARG];
        return -1;
    }
    // XXX check for listener active state
    
    //XXX detect no listeners (EBUS) error
    use_eos = ( termination != STOPend );
    retval = [self config_read_eos:board : use_eos : termination : YES];
    if( retval < 0 )
    {
        return retval;
    }
    
    retval = (int)[self read_data:conf : buffer : count : &bytes_read];
    [self setIbcnt:bytes_read];
    if(retval < 0)
    {
        return -1;
    }
    
    return 0;
}

-(int) InternalReceive:(ibConf_t *) conf : (uint16_t) address : (void *) buffer : (long) count : (int) termination
{
    int retval;
    
    retval = [self InternalReceiveSetup:conf : address];
    if( retval < 0 ) return retval;
    
    retval = [self InternalRcvRespMsg:conf : buffer : count : termination];
    if( retval < 0 )return retval;
    
    return 0;
}

-(int) InternalResetSys:(ibConf_t *) conf : (uint16_t *) addressList
{
    gpib_link *board;
    int retval;
    
    board = [self interfaceBoard:conf];
    
    if( [self addressListIsValid:addressList] == 0 )
    {
        [self setIberr:EARG];
        return -1;
    }
    
    if( conf->is_interface == 0 )
    {
        [self setIberr:EDVR];
        return -1;
    }
    
    if( [self is_system_controller:board] == 0 )
    {
        [self setIberr:ESAC];
        return -1;
    }
    
    if( [self is_cic:board] == NO )
    {
        [self setIberr:ECIC];
        return -1;
    }
    
    retval = [self remote_enable:board : YES];
    if( retval < 0 ) return retval;
    
    retval = [self internal_ibsic:conf];
    if( retval < 0 ) return retval;
    
    retval = [self InternalDevClearList:conf : nil];
    if( retval < 0 ) return retval;
    
    retval = [self InternalSendList:conf : addressList : "*RST" : 4 : NLend];
    if( retval < 0 ) return retval;
    
    return 0;
}

-(int) local_lockout:(ibConf_t *) conf : (uint16_t *) addressList
{
    UInt8 cmd;
    int retval;
    
    retval = [self InternalEnableRemote:conf : addressList];
    if( retval < 0 ) return retval;
    
    cmd = LLO;
    retval = (int)[self my_ibcmd:conf : &cmd : YES];
    if( retval < 0 ) return retval;
    
    return 0;
}

-(int) InternalTestSys:(ibConf_t *) conf : (uint16_t *) addressList : (short *) resultList
{
    UInt8 failure_count = 0;
    gpib_link *board;
    int retval;
    int i;
    
    if( conf->is_interface == 0 )
    {
        [self setIberr:EDVR];
        return -1;
    }
    
    board = [self interfaceBoard:conf];
    if( [self is_cic:board] == NO )
    {
        [self setIberr:ECIC];
        return -1;
    }
    
    if( [self addressListIsValid:addressList] == 0 )
    {
        [self setIberr:EARG];
        return -1;
    }
    
    if( [self numAddresses:addressList] == 0 )
    {
        [self setIberr:EARG];
        return -1;
    }
    
    retval = [self InternalSendList:conf : addressList : "*TST?" : 4 : NLend];
    if( retval < 0 ) return retval;
    
    for( i = 0; i < [self numAddresses:addressList]; i++ )
    {
        char reply[ 16 ];
        
        retval = [self InternalReceive:conf : addressList[i] : reply : sizeof( reply ) - 1 : STOPend];
        if( retval < 0 )
            return -1;
        
        reply[ [self ThreadIbcnt] ] = 0;
        resultList[ i ] = strtol( reply, NULL, 0 );
        
        if( resultList[ i ] )
            failure_count++;
    }
    
    [self setIbcnt:failure_count];
    
    return 0;
}

-(uint16_t) packAddress:(UInt8) pad : (int) sad
{
    uint16_t address;
    
    address = 0;
    address |= pad & 0xff;
    if( sad >= 0 )
        address |= ( ( sad | sad_offset ) << 8 ) & 0xff00;
    
    return address;
}

-(int) ibBoardOpen:(int) boardId
{
    gpib_link* board;
    int retval = 0;
    if([board_list count] > 0 && [board_list count] > boardId)
    {
        board = [board_list objectAtIndex:boardId];
        if(board != nil)
        {
            retval = [board ibopen];
        }
    }
    return retval;
}

-(int) ibBoardClose:(int) boardId
{
    gpib_link* board;
    int retval = 0;
    if([board_list count] > 0 && [board_list count] > boardId)
    {
        board = [board_list objectAtIndex:boardId];
        if(board != nil)
        {
            retval = [board ibclose];
        }
    }
    return retval;
}

-(int) configure_autospoll:(ibConf_t *) conf : (BOOL) enable
{
    //autospoll_ioctl_t spoll_enable = enable != 0;
    int retval = 0;
    gpib_link *board = [self interfaceBoard:conf];
    gpib_link_arg* arg = [[gpib_link_arg alloc] init];
    arg->cmd = IBAUTOSPOLL;
    arg->bEnable = enable;

    if((enable && [board isAutoSpoll] == NO) ||
       (enable == NO && [board isAutoSpoll]))
    {
        //retval = ioctl(interfaceBoard(conf)->fileno, IBAUTOSPOLL, &spoll_enable);
        retval = [board ioctl:arg];
        if(retval)
        {
            fprintf(stderr, "libmacosx_gpib: autospoll ioctl returned error %i\n", retval);
        }
        else
        {
            [board setAutoSpoll:enable];
        }
    }
    return retval;
}

-(int) conf_lock_board:(ibConf_t *) conf
{
    gpib_link *board;
    int retval;
    
    board = [self interfaceBoard:conf];
    
    assert( conf->has_lock == 0 );
    
    retval = [self lock_board_mutex:board];
    if( retval < 0 ) return retval;
    
    conf->has_lock = 1;
    
    return retval;
}

-(int) lock_board_mutex:(gpib_link *) board
{
    int retval;
    gpib_link_arg* arg = [[gpib_link_arg alloc] init];
    arg->cmd = IBMUTEX;
    arg->bMutex = YES;
    
    //retval = ioctl( board->fileno, IBMUTEX, &lock );
    retval = [board ioctl:arg];
    if( retval < 0 )
    {
        fprintf( stderr, "libmacosx_gpib: error locking board mutex!\n");
        [self setIberr:EDVR];
        [self setIbcnt:errno];
    }
    
    return retval;
}

-(int) unlock_board_mutex:(gpib_link *) board
{
    int retval;
    gpib_link_arg* arg = [[gpib_link_arg alloc] init];
    arg->cmd = IBMUTEX;
    arg->bMutex = NO;
    //retval = ioctl( board->fileno, IBMUTEX, &unlock );
    retval = [board ioctl:arg];
    if( retval < 0 )
    {
        fprintf( stderr, "libmacosx_gpib: error unlocking board mutex!\n");
        [self setIberr:EDVR];
        [self setIbcnt:errno];
    }
    return retval;
}

-(int) gpibi_change_address:(ibConf_t *) conf : (UInt8) pad : (int) sad
{
    int retval;
    gpib_link *board;
    gpib_link_arg* arg = [[gpib_link_arg alloc] init];
    arg->cmd = IBPAD;
    arg->pad = pad;
    arg->handle = conf->handle;
    
    board = [self interfaceBoard:conf];
    
    retval = [board ioctl:arg];
    if( retval < 0 )
    {
        [self setIberr:EDVR];
        [self setIbcnt:errno];
        return retval;
    }
    
    arg->cmd = IBSAD;
    arg->sad = sad;
    //retval = ioctl( board->fileno, IBSAD, &sad_cmd );
    retval = [board ioctl:arg];
    if( retval < 0 )
    {
        [self setIberr:EDVR];
        [self setIbcnt:errno];
        return retval;
    }
    
    conf->settings.pad = pad;
    conf->settings.sad = sad;
    
    return 0;
}

-(void) do_aio:(gpib_aio_arg *)arg
{
    size_t count = 0;
    ibConf_t *conf = arg->conf;
    int retval = 0;
    //gpib_link *board = [self interfaceBoard:arg->conf];
    //retval = [self lock_board_mutex:board];
    if(retval == 0)
    {
        retval = (int)[self ibstatus:conf : 0 : CMPL : 0];
    }
    
    if( retval < 0 ) return;
    
    if (![[NSThread currentThread]  isCancelled]) {
        switch( arg->gpib_aio_type )
        {
            case GPIB_AIO_COMMAND:
                retval = (int)[self my_ibcmd:conf : conf->async->buffer : conf->async->buffer_length];
                break;
            case GPIB_AIO_READ:
                retval = (int)[self my_ibrd:conf : conf->async->buffer : conf->async->buffer_length : &count];
                break;
            case GPIB_AIO_WRITE:
                retval = (int)[self my_ibwrt:conf : conf->async->buffer : conf->async->buffer_length : &count];
                break;
            default:
                retval = -1;
                fprintf( stderr, "libmacosx_gpib: bug! in %s\n", __FUNCTION__ );
                break;
        }
    }

    if(retval < 0)
    {
        if([self ThreadIberr] != EDVR)
            conf->async->ibcntl = count;
        else
            conf->async->ibcntl = [self ThreadIbcnt];
        conf->async->iberr = [self ThreadIberr];
        conf->async->ibsta = CMPL | ERR;
    }else
    {
        conf->async->ibcntl = count;
        conf->async->iberr = 0;
        conf->async->ibsta = CMPL;
    }
    //arg->condition_flag = YES;
    [self ibstatus:arg->conf : 0 : 0 : CMPL];
    //[self unlock_board_mutex:board];
    [[NSThread currentThread] cancel];
}

-(void) gpib_visa_asynch_thread//:(NSCondition*) condition
{
    @autoreleasepool {
        NSRunLoop *runLoop = [NSRunLoop currentRunLoop];
        while ([[NSThread currentThread] isCancelled]==NO)
        {
            [runLoop runMode:NSDefaultRunLoopMode beforeDate:[NSDate distantFuture]]; // starting infinite loop which can be stopped by changing the shouldKeepRunning's value
        }
    }
    [NSThread exit];
}

-(int) gpib_aio_launch:(int) ud : (ibConf_t *) conf : (int) gpib_aio_type : (void *) buffer : (long) cnt        
{
    int retval = 0;
    gpib_aio_arg *arg = [[gpib_aio_arg alloc] init];
    arg->ud = ud;
    arg->conf = conf;
    arg->gpib_aio_type = gpib_aio_type;
    arg->count = 0;
    
    pthread_mutex_lock( &conf->async->lock );
    conf->async->in_progress = YES;
    conf->async->ibsta = 0;
    conf->async->ibcntl = 0;
    conf->async->iberr = 0;
    conf->async->buffer = buffer;
    conf->async->buffer_length = cnt;
    conf->async->abort = 0;
    conf->async->thread = [[NSThread alloc] initWithTarget:self selector:@selector(gpib_visa_asynch_thread) object:nil];

    [conf->async->thread start];

    while([conf->async->thread isExecuting]==NO);

    [self performSelector:@selector(do_aio:) onThread:conf->async->thread withObject:arg waitUntilDone:YES];
    
    conf->async->thread = nil;
    conf->async->in_progress = NO;
    pthread_mutex_unlock( &conf->async->lock );

    if( retval )
    {
        [self setIberr:EDVR];
        [self setIbcnt:retval];
        return -1;
    }
    
    return 0;
}

-(int) iblcleos:(ibConf_t *) conf
{
    BOOL use_eos, compare8;
    
    use_eos = conf->settings.eos_flags & REOS;
    compare8 = conf->settings.eos_flags & BIN;
    
    return [self config_read_eos:[self interfaceBoard:conf] : use_eos : conf->settings.eos : compare8] ;
}

-(int) close_gpib_handle:(ibConf_t *)conf
{
    gpib_link_arg* arg = [[gpib_link_arg alloc] init];
    arg->cmd = IBCLOSEDEV;
    int retval;
    gpib_link *board;
    
    if( conf->handle < 0 ) return 0;
    arg->handle = conf->handle;
    board = [self interfaceBoard:conf];

    retval = [board ioctl:arg];
    if( retval < 0 )
    {
        [self setIberr:EDVR];
        [self setIbcnt:errno];
        return retval;
    }
    
    conf->handle = -1;
    
    return 0;
}

-(int) config_read_eos:(gpib_link *) board : (BOOL) use_eos_char : (int) eos_char : (BOOL) compare_8_bits
{
    int eos, eos_flags;
    int retval;
    
    eos_flags = 0;
    if( use_eos_char )
        eos_flags |= REOS;
    if( compare_8_bits )
        eos_flags |= BIN;
    
    eos = 0;
    if( use_eos_char )
    {
        eos = eos_char;
        eos &= 0xff;
        if( eos != eos_char )
        {
            [self setIberr:EARG];
            fprintf(stderr, "libmacosx_gpib: eos char more than 8 bits?\n");
            return -1;
        }
    }
    
    retval = [board ibeos:eos :eos_flags];
    if( retval < 0 )
    {
        [self setIberr:EDVR];
        [self setIbcnt:errno];
        fprintf(stderr, "libmacosx_gpib: IBEOS ioctl failed\n");
    }
    
    return retval;
}

-(int) exit_library:(int) ud : (BOOL) error
{
    return [self general_exit_library:ud : error : NO : NO : 0 : 0 : NO];
}

-(void) conf_unlock_board:(ibConf_t *) conf
{
    gpib_link *board;
    int retval;
    
    board = [self interfaceBoard:conf];

    assert( conf->has_lock );
    
    conf->has_lock = 0;
    
    retval = [self unlock_board_mutex:board];
    assert( retval == 0 );
}

-(void) sync_globals
{
    ibsta = [self ThreadIbsta];
    iberr = [self ThreadIberr];
    ibcntl = [self ThreadIbcnt];
    ibcnt = (int)ibcntl;
}

-(int) open_gpib_handle:(ibConf_t *) conf
{
    gpib_link_arg* arg = [[gpib_link_arg alloc] init];
    arg->cmd = IBOPENDEV;
    int retval;
    gpib_link *board;

    if( conf->handle >= 0 ) return 0;
    
    board = [self interfaceBoard:conf];
    arg->pad = conf->settings.pad;
    arg->sad = conf->settings.sad;
    arg->bIsBoard = conf->is_interface;
    retval = [board ioctl:arg];
    if( retval < 0 )
    {
        fprintf( stderr, "libmacosx_gpib: IBOPENDEV ioctl failed\n" );
        [self setIberr:EDVR];
        [self setIbcnt:errno];
        return retval;
    }
    
    conf->handle = arg->handle;
    
    return 0;
}

-(unsigned int) usec_to_timeout:(unsigned int) usec
{
    if( usec == 0 ) return TNONE;
    else if( usec <= 10 ) return T10us;
    else if( usec <= 30 ) return T30us;
    else if( usec <= 100 ) return T100us;
    else if( usec <= 300 ) return T300us;
    else if( usec <= 1000 ) return T1ms;
    else if( usec <= 3000 ) return T3ms;
    else if( usec <= 10000 ) return T10ms;
    else if( usec <= 30000 ) return T30ms;
    else if( usec <= 100000 ) return T100ms;
    else if( usec <= 300000 ) return T300ms;
    else if( usec <= 1000000 ) return T1s;
    else if( usec <= 3000000 ) return T3s;
    else if( usec <= 10000000 ) return T10s;
    else if( usec <= 30000000 ) return T30s;
    else if( usec <= 100000000 ) return T100s;
    else if( usec <= 300000000 ) return T300s;
    else if( usec <= 1000000000 ) return T1000s;
    
    return TNONE;
}

-(int) ibFindDevIndex:(char *) name
{
    int i;
    
    if( strcmp( "", name ) == 0 ) return -1;
    
    for(i = 0; i < FIND_CONFIGS_LENGTH; i++)
    {
        if(!strcmp(ibFindConfigs[i]->name, name)) return i;
    }
    
    return -1;
}

-(int) ibstatus:(ibConf_t *) conf : (BOOL) error : (int) clear_mask : (int) set_mask
{
    int status = 0;
    int retval;
    
    retval = [self my_wait:conf : 0 : clear_mask : set_mask : &status];
    
    if( retval < 0 )
        error = YES;

    if( error == YES ) status |= ERR;
    
    if( conf->timed_out )
        status |= TIMO;
    if( conf->end )
        status |= END;

    [self setIbsta:status];
    
    return status;
}

-(int) my_ibdev:(ibConf_t*) new_conf
{
    int ud;
    ibConf_t *conf;
    
    ud = [self ibGetDescriptor:new_conf];
    if( ud < 0 )
    {
        fprintf( stderr, "libmacosx_gpib: ibdev failed to get descriptor\n" );
        [self setIbsta:ERR];
        return -1;
    }
    
    conf = [self enter_library:ud];
    if( conf == NULL )
    {
        [self exit_library:ud : 1];
        return -1;
    }
    // XXX do local lockout if appropriate
    
    [self exit_library:ud : 0];
    return ud;
}

-(ibConf_t *) enter_library:(int) ud
{
    return [self general_enter_library:ud : NO : NO];
}

-(ibConf_t *) general_enter_library:(int) ud : (BOOL) no_lock_board : (BOOL) ignore_eoip
{
    ibConf_t *conf;
    int retval;
    
    [self setIberr:0];
    [self setIbcnt:0];
    
    if( [self ibCheckDescriptor:ud] < 0 )
    {
        return nil;
    }
    conf = ibConfigs[ ud ];
    
    retval = [self conf_online:conf : YES];
    if( retval < 0 ) return NULL;
    
    conf->timed_out = 0;
        
    if( no_lock_board == NO )
    {
        if( ignore_eoip == NO )
        {
            pthread_mutex_lock( &conf->async->lock );
            if( conf->async->in_progress )
            {
                pthread_mutex_unlock( &conf->async->lock );
                [self setIberr:EOIP];
                return NULL;
            }
            pthread_mutex_unlock( &conf->async->lock );
        }
        
        retval = [self conf_lock_board:conf];
        if( retval < 0 )
        {
            return NULL;
        }
    }
    
    return conf;
}

+(uint16_t) MakeAddr:(UInt8) pad : (UInt8) sad;
{
    uint16_t address;
    
    address = ( pad & 0xff );
    address |= ( sad << 8 ) & 0xff00;
    return address;
}

+(UInt8) GetPAD:(uint16_t) address;
{
    return address & 0xff;
}

+(UInt8) GetSAD:(uint16_t) address;
{
    return ( address >> 8 ) & 0xff;
}


@end
