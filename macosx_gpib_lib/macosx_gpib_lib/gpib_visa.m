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
#import "gpib_visa.h"
#import "Agilent_82357_AB.h"
#import "gpib_visa_internal.h"

const char GPIB_SCM_VERSION[6] = "1.0.3a";

@implementation gpib_visa

-(id) init
{
    self = [super init];
    printf("macosx_gpib_lib version %s  Copyright (C) 2018  by Guilhem Vavelin\n"
           "This program comes with ABSOLUTELY NO WARRANTY;\n"
           "This is free software, and you are welcome to redistribute it under the\n"
           "terms of the GNU General Public License as published by the Free Software\n"
           "Foundation version 2; email:guileukow@users.sourceforge.net\n\n", GPIB_SCM_VERSION);
    m_gpib_visa_internal = [[gpib_visa_internal alloc] init];
    return self;
}

-(void) close
{
    [m_gpib_visa_internal close];
}

-(int) ibclose:(int) boardID
{
    return [m_gpib_visa_internal ibBoardClose:boardID];
}

-(int) ibopen:(int) boardID
{
    return [m_gpib_visa_internal ibBoardOpen:boardID];
}

-(void) AllSPoll:(int) boardID : (uint16_t *) addressList : (short *) resultList
{
    int i;
    ibConf_t *conf;
    gpib_link *board;
    int retval;
    
    conf = [m_gpib_visa_internal enter_library:boardID];
    if( conf == NULL )
    {
        [m_gpib_visa_internal exit_library:boardID : YES];
        return;
    }
    if( [m_gpib_visa_internal addressListIsValid:addressList] == NO )
    {
        [m_gpib_visa_internal exit_library:boardID : YES];
        return;
    }
    
    if( conf->is_interface == NO )
    {
        [m_gpib_visa_internal setIberr:EDVR];
        [m_gpib_visa_internal exit_library:boardID : YES];
        return;
    }
    
    board = [m_gpib_visa_internal interfaceBoard:conf];
    
    if( [m_gpib_visa_internal is_cic:board] == NO )
    {
        [m_gpib_visa_internal setIberr:ECIC];
        [m_gpib_visa_internal exit_library:boardID: YES];
        return;
    }
    
    // XXX could use slightly more efficient ALLSPOLL protocol
    retval = 0;
    for( i = 0; i < [m_gpib_visa_internal numAddresses:addressList]; i++ )
    {
        UInt8 result;
        retval = [m_gpib_visa_internal serial_poll:board : [m_gpib_visa_internal extractPAD:addressList[ i ]] :
                  [m_gpib_visa_internal extractSAD:addressList[ i ]] : conf->settings.spoll_usec_timeout : &result];
        if( retval < 0 )
        {
            if( errno == ETIMEDOUT )
                conf->timed_out = 1;
            break;
        }
        resultList[ i ] = result & 0xff;
    }
    [m_gpib_visa_internal setIbcnt:i];
    
    if( retval < 0 )
        [m_gpib_visa_internal exit_library:boardID : YES];
    else
        [m_gpib_visa_internal exit_library:boardID : NO];
}

-(void) AllSpoll:(int) boardID : (uint16_t *) addressList : (short *) resultList
{
    [self AllSPoll:boardID : addressList : resultList];
}

-(void) DevClear:(int) board_desc : (uint16_t) address
{
    uint16_t addressList[2];
    
    addressList[0] = address;
    addressList[1] = NOADDR;
    
    [self DevClearList:board_desc : addressList];
}

-(void) DevClearList:(int) board_desc : (uint16_t *) addressList
{
    int retval;
    ibConf_t *conf;
    
    conf = [m_gpib_visa_internal enter_library:board_desc];
    if( conf == NULL )
    {
        [m_gpib_visa_internal exit_library:board_desc : YES];
        return;
    }
    
    retval = [m_gpib_visa_internal InternalDevClearList:conf : addressList];
    if( retval < 0 )
        [m_gpib_visa_internal exit_library:board_desc : YES];
    
    [m_gpib_visa_internal exit_library:board_desc : NO];
}

-(void) EnableLocal:(int) boardID : (uint16_t *) addressList
{
    int i;
    ibConf_t *conf;
    gpib_link *board;
    UInt8 *cmd;
    int count;
    int retval;
    
    conf = [m_gpib_visa_internal enter_library:boardID];
    if( conf == NULL )
    {
        [m_gpib_visa_internal exit_library:boardID : YES];
        return;
    }
    if( [m_gpib_visa_internal addressListIsValid:addressList] == NO )
    {
        [m_gpib_visa_internal exit_library:boardID : YES];
        return;
    }
    
    if( conf->is_interface == 0 )
    {
        [m_gpib_visa_internal setIberr:EDVR];
        [m_gpib_visa_internal exit_library:boardID : YES];
        return;
    }
    
    board = [m_gpib_visa_internal interfaceBoard:conf];
    
    if( [m_gpib_visa_internal is_cic:board] == NO )
    {
        [m_gpib_visa_internal setIberr:ECIC];
        [m_gpib_visa_internal exit_library:boardID : YES];
        return;
    }
    
    if( [m_gpib_visa_internal numAddresses:addressList] == 0 )
    {
        retval = [m_gpib_visa_internal remote_enable:board : NO];
        if( retval < 0 )
            [m_gpib_visa_internal exit_library:boardID : YES];
        else
            [m_gpib_visa_internal exit_library:boardID : NO];
        return;
    }
    
    cmd = malloc( 16 + 2 * [m_gpib_visa_internal numAddresses:addressList] );
    if( cmd == NULL )
    {
        [m_gpib_visa_internal setIberr:EDVR];
        [m_gpib_visa_internal setIbcnt:ENOMEM];
        [m_gpib_visa_internal exit_library:boardID : YES];
        return;
    }
    
    i = [m_gpib_visa_internal create_send_setup:board : addressList : cmd];
    cmd[ i++ ] = GTL;
    
    //XXX detect no listeners (EBUS) error
    count = (int)[m_gpib_visa_internal my_ibcmd:conf : cmd : i];
    
    free( cmd );
    cmd = NULL;
    
    if(count != i)
    {
        [m_gpib_visa_internal exit_library:boardID : YES];
        return;
    }
    
    [m_gpib_visa_internal exit_library:boardID : NO];
}

-(void) EnableRemote:(int) boardID : (uint16_t *) addressList
{
    ibConf_t *conf;
    int retval;
    
    conf = [m_gpib_visa_internal enter_library:boardID];
    if( conf == NULL )
    {
        [m_gpib_visa_internal exit_library:boardID: YES];
        return;
    }
    
    retval = [m_gpib_visa_internal InternalEnableRemote:conf : addressList];
    if( retval < 0 )
    {
        [m_gpib_visa_internal exit_library:boardID: YES];
        return;
    }
    
    [m_gpib_visa_internal exit_library:boardID: NO];
}

-(void) FindLstn:(int) boardID : (uint16_t *) padList : (uint16_t *) resultList : (int) maxNumResults
{
    int i;
    ibConf_t *conf;
    int retval;
    int resultIndex;
    short line_status;
    
    conf = [m_gpib_visa_internal enter_library:boardID];
    if( conf == NULL )
    {
        [m_gpib_visa_internal exit_library:boardID : YES];
        return;
    }
    
    if( conf->is_interface == 0 )
    {
        [m_gpib_visa_internal setIberr:EDVR];
        [m_gpib_visa_internal exit_library:boardID : YES];
        return;
    }
        
    retval = [m_gpib_visa_internal internal_iblines:conf : &line_status];
    if( retval < 0 )
    {
        [m_gpib_visa_internal exit_library:boardID : YES];
        return;
    }
    if( ( line_status & ValidNDAC ) == 0 )
    {
        [m_gpib_visa_internal setIberr:ECAP];
        [m_gpib_visa_internal exit_library:boardID : YES];
        return;
    }
    
    resultIndex = 0;
    for( i = 0; i < [m_gpib_visa_internal numAddresses:padList]; i++ )
    {
        uint16_t pad;
        uint16_t testAddress[ 2 ];
        
        pad = [gpib_visa_internal GetPAD:padList[ i ]];
        testAddress[ 0 ] = pad;
        testAddress[ 1 ] = NOADDR;
        retval = [m_gpib_visa_internal listenerFound:conf : testAddress];
        if( retval < 0 )
        {
            // XXX status/error settings
            [m_gpib_visa_internal exit_library:boardID: YES];
            return;
        }
        if( retval > 0 )
        {
            if( resultIndex >= maxNumResults )
            {
                [m_gpib_visa_internal setIberr:ETAB];
                [m_gpib_visa_internal exit_library:boardID: YES];
                return;
            }
            resultList[ resultIndex++ ] = testAddress[ 0 ];
            [m_gpib_visa_internal setIbcnt:resultIndex];
        }else
        {
            retval = [m_gpib_visa_internal secondaryListenerFound:conf : pad];
            if( retval < 0 )
            {
                [m_gpib_visa_internal exit_library:boardID: YES];
                return;
            }
            if( retval > 0 )
            {
                int j;
                for( j = 0; j <= gpib_addr_max; j++ )
                {
                    testAddress[ 0 ] = [m_gpib_visa_internal packAddress:pad :j];
                    testAddress[ 1 ] = NOADDR;
                    retval = [m_gpib_visa_internal listenerFound:conf : testAddress];
                    if( retval < 0 )
                    {
                        [m_gpib_visa_internal exit_library:boardID: YES];
                        return;
                    }
                    if( retval > 1 )
                    {
                        if( resultIndex >= maxNumResults )
                        {
                            [m_gpib_visa_internal setIberr:ETAB];
                            [m_gpib_visa_internal exit_library:boardID: YES];
                            return;
                        }
                        resultList[ resultIndex++ ] = testAddress[ 0 ];
                        [m_gpib_visa_internal setIbcnt:resultIndex];
                    }
                }
            }
        }
    }
    [m_gpib_visa_internal exit_library:boardID: NO];
} // FindLstn

-(void) FindRQS:(int) boardID : (uint16_t *) addressList : (short *) result
{
    int i;
    ibConf_t *conf;
    gpib_link *board;
    int retval;
    
    conf = [m_gpib_visa_internal enter_library:boardID];
    if( conf == NULL )
    {
        [m_gpib_visa_internal exit_library:boardID : YES];
        return;
    }
    if( [m_gpib_visa_internal addressListIsValid:addressList] == NO )
    {
        [m_gpib_visa_internal exit_library:boardID : YES];
        return;
    }
    
    if( conf->is_interface == 0 )
    {
        [m_gpib_visa_internal setIberr:EDVR];
        [m_gpib_visa_internal exit_library:boardID : YES];
        return;
    }
    
    board = [m_gpib_visa_internal interfaceBoard:conf];
    
    if( [m_gpib_visa_internal is_cic:board] == NO )
    {
        [m_gpib_visa_internal setIberr:ECIC];
        [m_gpib_visa_internal exit_library:boardID : YES];
        return;
    }
    
    retval = 0;
    for( i = 0; i < [m_gpib_visa_internal numAddresses:addressList]; i++ )
    {
        UInt8 spoll_byte;
        retval = [m_gpib_visa_internal serial_poll:board : [m_gpib_visa_internal extractPAD:addressList[i]] :
                  [m_gpib_visa_internal extractSAD:addressList[i]] : conf->settings.usec_timeout : &spoll_byte];
        if( retval < 0 )
        {
            if( errno == ETIMEDOUT )
                conf->timed_out = 1;
            break;
        }
        if( spoll_byte & request_service_bit )
        {
            *result = spoll_byte & 0xff;
            break;
        }
    }
    [m_gpib_visa_internal setIbcnt:i];
    if( i == [m_gpib_visa_internal numAddresses:addressList] )
    {
        [m_gpib_visa_internal setIberr:ETAB];
        retval = -1;
    }
    
    if( retval < 0 )
        [m_gpib_visa_internal exit_library:boardID : YES];
    else
        [m_gpib_visa_internal exit_library:boardID : NO];
}

-(void) PassControl:(int) boardID : (uint16_t) address
{
    ibConf_t *conf;
    int retval;
    
    conf = [m_gpib_visa_internal enter_library:boardID];
    if( conf == NULL )
    {
        [m_gpib_visa_internal exit_library:boardID : YES];
        return;
    }
    
    if( [m_gpib_visa_internal addressIsValid:address] == 0 )
    {
        [m_gpib_visa_internal exit_library:boardID: YES];
        return;
    }
    
    if( conf->is_interface == 0 )
    {
        [m_gpib_visa_internal setIberr:EARG];
        [m_gpib_visa_internal exit_library:boardID : YES];
        return;
    }
    
    retval = [m_gpib_visa_internal my_pass_control:conf : [m_gpib_visa_internal extractPAD:address] : [m_gpib_visa_internal extractSAD:address]] ;
    if( retval < 0 )
    {
        [m_gpib_visa_internal exit_library:boardID : YES];
        return;
    }
    
    [m_gpib_visa_internal exit_library:boardID: NO];
}

-(void) PPoll:(int) boardID : (short *) result
{
    char byte_result;
    ibConf_t *conf;
    int retval=0;

    conf = [m_gpib_visa_internal enter_library:boardID];
    if( conf == NULL )
    {
        [m_gpib_visa_internal exit_library:boardID : YES];
        return;
    }
    
    if( conf->is_interface == 0 )
    {
        [m_gpib_visa_internal setIberr:EARG];
        [m_gpib_visa_internal exit_library:boardID : YES];
        return;
    }
    retval = [m_gpib_visa_internal internal_ibrpp:conf : &byte_result];
    if( retval < 0 )
    {
        [m_gpib_visa_internal exit_library:boardID : YES];
        return;
    }
    
    *result = byte_result & 0xff;
    
    [m_gpib_visa_internal exit_library:boardID : NO];
}

-(void) PPollConfig:(int) boardID : (uint16_t) address : (int) dataLine : (int) lineSense
{
    ibConf_t *conf;
    int retval;
    int ppoll_config;
    uint16_t addressList[ 2 ];
    
    conf = [m_gpib_visa_internal enter_library:boardID];
    if( conf == NULL )
    {
        [m_gpib_visa_internal exit_library:boardID : YES];
        return;
    }
    
    if( conf->is_interface == 0 )
    {
        [m_gpib_visa_internal setIberr:EDVR];
        [m_gpib_visa_internal exit_library:boardID : YES];
        return;
    }
    
    if( dataLine < 1 || dataLine > 8 || [m_gpib_visa_internal addressIsValid:address] == 0 || address == NOADDR )
    {
        [m_gpib_visa_internal setIberr:EARG];
        [m_gpib_visa_internal exit_library:boardID : YES];
        return;
    }
    
    ppoll_config = PPE_byte( dataLine, lineSense );
    
    addressList[ 0 ] = address;
    addressList[ 1 ]= NOADDR;
    retval = [m_gpib_visa_internal ppoll_configure_device:conf : addressList : ppoll_config];
    if( retval < 0 )
    {
        [m_gpib_visa_internal exit_library:boardID : YES];
        return;
    }
    
    [m_gpib_visa_internal exit_library:boardID : NO];
}

-(void) PPollUnconfig:(int) boardID : (uint16_t *) addressList
{
    ibConf_t *conf;
    int retval;
    
    conf = [m_gpib_visa_internal enter_library:boardID];
    if( conf == NULL )
    {
        [m_gpib_visa_internal exit_library:boardID : YES];
        return;
    }
    
    if( conf->is_interface == 0 )
    {
        [m_gpib_visa_internal setIberr:EDVR];
        [m_gpib_visa_internal exit_library:boardID : YES];
        return;
    }
    
    if( [m_gpib_visa_internal addressListIsValid:addressList] == NO )
    {
        [m_gpib_visa_internal setIberr:EARG];
        [m_gpib_visa_internal exit_library:boardID : YES];
        return;
    }
    
    if( [m_gpib_visa_internal numAddresses:addressList] )
    {
        retval = [m_gpib_visa_internal ppoll_configure_device:conf : addressList : PPD];
    }else
    {
        UInt8 cmd = PPU;
        
        retval = (int)[m_gpib_visa_internal my_ibcmd:conf : &cmd : YES];
    }
    if( retval < 0 )
    {
        [m_gpib_visa_internal exit_library:boardID : YES];
        return;
    }
    
    [m_gpib_visa_internal exit_library:boardID : NO];
}

-(void) RcvRespMsg:(int) boardID : (void *) buffer : (long) count : (int) termination
{
    ibConf_t *conf;
    int retval;
    
    conf = [m_gpib_visa_internal enter_library:boardID];
    if( conf == NULL )
    {
        [m_gpib_visa_internal exit_library:boardID : YES];
        return;
    }
    
    retval = [m_gpib_visa_internal InternalRcvRespMsg:conf : buffer : count : termination];
    if( retval < 0 )
    {
        [m_gpib_visa_internal exit_library:boardID : YES];
        return;
    }
    
    [m_gpib_visa_internal general_exit_library:boardID : NO : NO : NO : DCAS : 0 : NO];
}

-(void) ReadStatusByte:(int) boardID : (uint16_t) address : (short *) result
{
    ibConf_t *conf;
    gpib_link *board;
    UInt8 byte_result;
    int retval;
    
    conf = [m_gpib_visa_internal enter_library:boardID];
    if( conf == NULL )
    {
        [m_gpib_visa_internal exit_library:boardID : YES];
        return;
    }
    if( [m_gpib_visa_internal addressIsValid:address] == 0 )
    {
        [m_gpib_visa_internal exit_library:boardID : YES];
        return;
    }
    
    if( conf->is_interface == 0 )
    {
        [m_gpib_visa_internal setIberr:EDVR];
        [m_gpib_visa_internal exit_library:boardID : YES];
        return;
    }
    
    board = [m_gpib_visa_internal interfaceBoard:conf];
    
    if( [m_gpib_visa_internal is_cic:board] == NO )
    {
        [m_gpib_visa_internal setIberr:ECIC];
        [m_gpib_visa_internal exit_library:boardID : YES];
        return;
    }
    
    retval = [m_gpib_visa_internal serial_poll:board : [m_gpib_visa_internal extractPAD:address] :
              [m_gpib_visa_internal extractSAD:address] : conf->settings.spoll_usec_timeout : &byte_result];
    if( retval < 0 )
    {
        if( errno == ETIMEDOUT )
            conf->timed_out = 1;
        [m_gpib_visa_internal exit_library:boardID : YES];
        return;
    }
    *result = byte_result & 0xff;
    
    [m_gpib_visa_internal exit_library:boardID : NO];
}

-(void) Receive:(int) boardID : (uint16_t) address : (void *) buffer : (long) count : (int) termination
{
    ibConf_t *conf;
    int retval;
    
    conf = [m_gpib_visa_internal enter_library:boardID];
    if( conf == NULL )
    {
        [m_gpib_visa_internal exit_library:boardID : YES];
        return;
    }
    
    retval = [m_gpib_visa_internal InternalReceive:conf : address : buffer : count : termination];
    if( retval < 0 )
    {
        [m_gpib_visa_internal exit_library:boardID : YES];
        return;
    }
    
    [m_gpib_visa_internal general_exit_library:boardID : NO : NO : NO : DCAS : 0 : NO];
}

-(void) ReceiveSetup:(int) boardID : (uint16_t) address
{
    ibConf_t *conf;
    int retval;
    
    conf = [m_gpib_visa_internal enter_library:boardID];
    if( conf == NULL )
    {
        [m_gpib_visa_internal exit_library:boardID : YES];
        return;
    }
    
    retval = [m_gpib_visa_internal InternalReceiveSetup:conf : address];
    if( retval < 0 )
    {
        [m_gpib_visa_internal exit_library:boardID : YES];
        return;
    }
    
    [m_gpib_visa_internal exit_library:boardID : NO];
}

-(void) ResetSys:(int) boardID : (uint16_t *) addressList
{
    ibConf_t *conf;
    int retval;
    
    conf = [m_gpib_visa_internal enter_library:boardID];
    if( conf == NULL )
    {
        [m_gpib_visa_internal exit_library:boardID : YES];
        return;
    }
    
    retval = [m_gpib_visa_internal InternalResetSys:conf : addressList];
    if( retval < 0 )
    {
        [m_gpib_visa_internal exit_library:boardID : YES];
        return;
    }
    
    [m_gpib_visa_internal exit_library:boardID : NO];
    
}

-(void) Send:(int) boardID : (uint16_t) address : (void *) buffer : (long) count : (int) eot_mode
{
    uint16_t addressList[ 2 ];
    
    addressList[ 0 ] = address;
    addressList[ 1 ] = NOADDR;
    
    [self SendList:boardID : addressList : buffer : count : eot_mode];
}

-(void) SendCmds:(int) boardID : (void *) buffer : (long) count
{
    [self ibcmd: boardID : buffer : count];
}

-(void) SendDataBytes:(int) boardID : (void *) buffer : (long) count : (int) eotmode
{
    ibConf_t *conf;
    int retval;
    
    conf = [m_gpib_visa_internal enter_library:boardID];
    if( conf == NULL )
    {
        [m_gpib_visa_internal exit_library:boardID : YES];
        return;
    }
    
    retval = [m_gpib_visa_internal InternalSendDataBytes:conf : buffer : count : eotmode];
    if( retval < 0 )
    {
        [m_gpib_visa_internal exit_library:boardID : YES];
        return;
    }
    
    [m_gpib_visa_internal general_exit_library:boardID: NO : NO : NO : DCAS : 0 : NO];
}

-(void) SendIFC:(int) boardID
{
    [self ibsic:boardID];
}

-(void) SendLLO:(int) boardID
{
    ibConf_t *conf;
    int retval;
    
    conf = [m_gpib_visa_internal enter_library:boardID];
    if( conf == NULL )
    {
        [m_gpib_visa_internal exit_library:boardID : YES];
        return;
    }
    
    retval = [m_gpib_visa_internal local_lockout:conf : nil];
    if( retval < 0 )
    {
        [m_gpib_visa_internal exit_library:boardID: YES];
        return;
    }
    
    [m_gpib_visa_internal exit_library:boardID : NO];
}

-(void) SendList:(int) boardID : (uint16_t *) addressList : (void *) buffer : (long) count : (int) eotmode
{
    ibConf_t *conf;
    int retval;
    
    conf = [m_gpib_visa_internal enter_library:boardID];
    if( conf == NULL )
    {
        [m_gpib_visa_internal exit_library:boardID : YES];
        return;
    }
    
    retval = [m_gpib_visa_internal InternalSendList:conf : addressList : buffer : count : eotmode];
    if( retval < 0 )
    {
        [m_gpib_visa_internal exit_library:boardID : YES];
        return;
    }
    [m_gpib_visa_internal general_exit_library:boardID : NO : NO : NO : DCAS : 0 : NO];
}

-(void) SendSetup:(int) boardID : (uint16_t *) addressList
{
    int retval;
    ibConf_t *conf;
    
    conf = [m_gpib_visa_internal enter_library:boardID];
    if( conf == NULL )
    {
        [m_gpib_visa_internal exit_library:boardID: YES];
        return;
    }
    
    retval = [m_gpib_visa_internal InternalSendSetup:conf:addressList];
    if( retval < 0 )
    {
        [m_gpib_visa_internal exit_library:boardID : YES];
        return;
    }
    
    [m_gpib_visa_internal exit_library:boardID : NO];
}

-(void) SetRWLS:(int) boardID : (uint16_t *) addressList
{
    ibConf_t *conf;
    int retval;
    
    conf = [m_gpib_visa_internal enter_library:boardID];
    if( conf == NULL )
    {
        [m_gpib_visa_internal exit_library:boardID : YES];
        return;
    }
    
    if( [m_gpib_visa_internal numAddresses:addressList] == 0 )
    {
        [m_gpib_visa_internal setIberr:EARG];
        [m_gpib_visa_internal exit_library:boardID : YES];
        return;
    }
    
    retval = [m_gpib_visa_internal local_lockout:conf : addressList];
    if( retval < 0 )
    {
        [m_gpib_visa_internal exit_library:boardID : YES];
        return;
    }
    
    [m_gpib_visa_internal exit_library:boardID: NO];
}

-(void) TestSRQ:(int) boardID : (short *) result
{
    short line_status;
    
    ibConf_t *conf;
    int retval;
    
    conf = [m_gpib_visa_internal general_enter_library:boardID : YES : NO];
    if( conf == NULL )
    {
        [m_gpib_visa_internal general_exit_library:boardID : YES : NO : NO : 0 : 0 : YES];
        return;
    }
    
    retval = [m_gpib_visa_internal internal_iblines:conf : &line_status];
    if( retval < 0 )
    {
        [m_gpib_visa_internal general_exit_library:boardID : YES : NO : NO : 0 : 0 : YES];
        return;
    }
    
    if( ( line_status & ValidSRQ ) == 0 )
    {
        [m_gpib_visa_internal setIberr:ECAP];
        [m_gpib_visa_internal general_exit_library:boardID : YES : NO : NO : 0 : 0 : YES];
        return;
    }
    
    if( line_status & BusSRQ )
    {
        *result = 1;
    }else
        *result = 0;
    
    [m_gpib_visa_internal general_exit_library:boardID : NO : NO : NO : 0 : 0 : YES];
}

-(void) TestSys:(int) boardID : (uint16_t *) addressList : (short *) resultList
{
    ibConf_t *conf;
    int retval;
    
    conf = [m_gpib_visa_internal enter_library:boardID];
    if( conf == NULL )
    {
        [m_gpib_visa_internal exit_library:boardID: YES];
        return;
    }
    
    retval = [m_gpib_visa_internal InternalTestSys:conf : addressList : resultList];
    if( retval < 0 )
    {
        [m_gpib_visa_internal exit_library:boardID : YES];
        return;
    }
    
    [m_gpib_visa_internal exit_library:boardID : NO];
}

-(void) Trigger:(int) boardID : (uint16_t *) address;
{
    uint16_t addressList[ 2 ];
    
    addressList[ 0 ] = *address;
    addressList[ 1 ] = NOADDR;
    
    [self TriggerList:boardID : addressList];
}

-(void) TriggerList:(int) boardID : (uint16_t *) addressList
{
    ibConf_t *conf;
    int retval;
    
    conf = [m_gpib_visa_internal enter_library:boardID];
    if( conf == NULL )
    {
        [m_gpib_visa_internal exit_library:boardID: YES];
        return;
    }
    
    if( conf->is_interface == 0 )
    {
        [m_gpib_visa_internal setIberr:EDVR];
        [m_gpib_visa_internal exit_library:boardID : YES];
        return;
    }
    
    retval = [m_gpib_visa_internal my_trigger:conf : addressList];
    if( retval < 0 )
    {
        [m_gpib_visa_internal exit_library:boardID : YES];
        return;
    }
    
    [m_gpib_visa_internal exit_library:boardID : NO];
}

-(void) WaitSRQ:(int) boardID : (short *) result
{
    ibConf_t *conf;
    int retval;
    int wait_mask;
    int status;
    
    conf = [m_gpib_visa_internal general_enter_library:boardID : YES : NO];
    if( conf == NULL )
    {
        [m_gpib_visa_internal general_exit_library:boardID : YES : NO : NO : 0 : 0 : YES];
        return;
    }
    
    if( conf->is_interface == 0 )
    {
        [m_gpib_visa_internal setIberr:EDVR];
        [m_gpib_visa_internal general_exit_library:boardID : YES : NO : NO : 0 : 0 : YES];
        return;
    }
    
    wait_mask = SRQI | TIMO;
    retval = [m_gpib_visa_internal my_wait:conf : wait_mask : 0 : 0 : &status];
    if( retval < 0 )
    {
        [m_gpib_visa_internal general_exit_library:boardID : YES : NO : NO : 0 : 0 : YES];
        return;
    }
    // XXX need better query of service request state, new ioctl?
    // should play nice with autopolling
    if( [m_gpib_visa_internal ThreadIbsta] & SRQI )
        *result = 1;
    else
        *result = 0;
    
    [m_gpib_visa_internal general_exit_library:boardID : NO : NO : NO : 0 : 0 : YES];
}

-(int) ibask:(int) boardID : (int) option : (int *) value
{
    ibConf_t *conf;
    gpib_link *board;
    int retval;
    
    conf = [m_gpib_visa_internal general_enter_library:boardID : YES : NO];
    if( conf == NULL )
        return [m_gpib_visa_internal exit_library:boardID: YES];
    
    board = [m_gpib_visa_internal interfaceBoard:conf];
    
    switch( option )
    {
        case IbaPAD:
            if( conf->is_interface )
            {
                UInt8 pad;
                
                retval = [m_gpib_visa_internal query_pad:board : &pad];
                if( retval < 0 )
                    return [m_gpib_visa_internal exit_library:boardID: YES];
                conf->settings.pad = pad;
            }
            *value = conf->settings.pad;
            return [m_gpib_visa_internal exit_library:boardID: NO];
            break;
        case IbaSAD:
            if( conf->is_interface )
            {
                int sad;
                retval = [m_gpib_visa_internal query_sad:board : &sad];
                if( retval < 0 )
                    return [m_gpib_visa_internal exit_library:boardID: YES];
                conf->settings.sad = sad;
            }
            if( conf->settings.sad < 0 ) *value = 0;
            else *value = MSA( conf->settings.sad );
            return [m_gpib_visa_internal exit_library:boardID: NO];
            break;
        case IbaTMO:
            *value = [m_gpib_visa_internal usec_to_timeout:conf->settings.usec_timeout];
            return [m_gpib_visa_internal exit_library:boardID: NO];
            break;
        case IbaEOT:
            *value = conf->settings.send_eoi;
            return [m_gpib_visa_internal exit_library:boardID: NO];
            break;
        case IbaEOSrd:
            *value = conf->settings.eos_flags & REOS;
            return [m_gpib_visa_internal exit_library:boardID: NO];
            break;
        case IbaEOSwrt:
            *value = conf->settings.eos_flags & XEOS;
            return [m_gpib_visa_internal exit_library:boardID: NO];
            break;
        case IbaEOScmp:
            *value = conf->settings.eos_flags & BIN;
            return [m_gpib_visa_internal exit_library:boardID: NO];
            break;
        case IbaEOSchar:
            *value = conf->settings.eos;
            return [m_gpib_visa_internal exit_library:boardID: NO];
            break;
        case IbaReadAdjust:
            /* XXX I guess I could implement byte swapping stuff,
             * it's pretty stupid though */
            *value = 0;
            return [m_gpib_visa_internal exit_library:boardID: NO];
            break;
        case IbaWriteAdjust:
            /* XXX I guess I could implement byte swapping stuff,
             * it's pretty stupid though */
            *value = 0;
            return [m_gpib_visa_internal exit_library:boardID: NO];
            break;
        case IbaEndBitIsNormal:
            /* XXX no support for setting END status on EOI only yet */
            *value = 1;
            return [m_gpib_visa_internal exit_library:boardID: NO];
            break;
        default:
            break;
    }
    
    if( conf->is_interface )
    {
        switch( option )
        {
            case IbaPPC:
                retval = [m_gpib_visa_internal query_ppc:board];
                if( retval < 0 )
                    return [m_gpib_visa_internal exit_library:boardID: YES];
                *value = retval;
                return [m_gpib_visa_internal exit_library:boardID: NO];
                break;
            case IbaAUTOPOLL:
                retval = [m_gpib_visa_internal query_autopoll:board];
                if( retval < 0 )
                    return [m_gpib_visa_internal exit_library:boardID: YES];
                *value = retval;
                return [m_gpib_visa_internal exit_library:boardID: NO];
                break;
            case IbaCICPROT:
                // XXX we don't support pass control protocol yet
                *value = 0;
                return [m_gpib_visa_internal exit_library:boardID: NO];
                break;
            case IbaIRQ:
                // XXX we don't support interrupt-less operation yet
                *value = 0;
                return [m_gpib_visa_internal exit_library:boardID: NO];
                break;
            case IbaSC:
                retval = [m_gpib_visa_internal is_system_controller:board];
                if( retval < 0 )
                    return [m_gpib_visa_internal exit_library:boardID: YES];
                *value = retval;
                return [m_gpib_visa_internal exit_library:boardID: NO];
                break;
            case IbaSRE:
                /* XXX pretty worthless, until changing
                 * system controllers is supported */
                *value = 1;
                return [m_gpib_visa_internal exit_library:boardID: NO];
                break;
            case IbaPP2:
                *value = conf->settings.local_ppc;
                return [m_gpib_visa_internal exit_library:boardID: NO];
                break;
            case IbaTIMING:
                retval = [m_gpib_visa_internal query_board_t1_delay:board];
                if( retval < 0 )
                    return [m_gpib_visa_internal exit_library:boardID: YES];
                *value = retval;
                return [m_gpib_visa_internal exit_library:boardID: NO];
                break;
            case IbaDMA:
                // XXX bogus, but pretty unimportant
                *value = -1;//board->dma;
                return [m_gpib_visa_internal exit_library:boardID: NO];
                break;
            case IbaEventQueue:
                *value = 0;//board->use_event_queue;
                return [m_gpib_visa_internal exit_library:boardID: NO];
                break;
            case IbaSPollBit:
                *value = 1;
                return [m_gpib_visa_internal exit_library:boardID: NO];
                break;
            case IbaSendLLO:
                *value = conf->settings.local_lockout;
                return [m_gpib_visa_internal exit_library:boardID: NO];
                break;
            case IbaPPollTime:
                *value = [m_gpib_visa_internal usec_to_ppoll_timeout:conf->settings.ppoll_usec_timeout];
                return [m_gpib_visa_internal exit_library:boardID: NO];
                break;
            case IbaHSCableLength:
                /* HS transfer not supported and may never
                 * be as it is not part of GPIB standard */
                *value = 0;
                return [m_gpib_visa_internal exit_library:boardID: NO];
                break;
            case IbaIst:
                retval = [m_gpib_visa_internal query_ist:board];
                if( retval < 0 )
                    return [m_gpib_visa_internal exit_library:boardID: YES];
                *value = retval;
                return [m_gpib_visa_internal exit_library:boardID: NO];
                break;
            case IbaRsv:
                retval = [m_gpib_visa_internal query_board_rsv:board];
                if( retval < 0 )
                    return [m_gpib_visa_internal exit_library:boardID: YES];
                *value = retval;
                return [m_gpib_visa_internal exit_library:boardID: NO];
                break;
            case Iba7BitEOS:
                retval = [m_gpib_visa_internal query_no_7_bit_eos:board];
                if( retval < 0 )
                    return [m_gpib_visa_internal exit_library:boardID: YES];
                *value = !retval;
                return [m_gpib_visa_internal exit_library:boardID: NO];
                break;
            default:
                break;
        }
    }else
    {
        switch( option )
        {
            case IbaREADDR:
                *value = conf->settings.readdr;
                return [m_gpib_visa_internal exit_library:boardID: NO];
                break;
            case IbaSPollTime:
                *value = [m_gpib_visa_internal usec_to_timeout:conf->settings.spoll_usec_timeout];
                return [m_gpib_visa_internal exit_library:boardID: NO];
                break;
            case IbaUnAddr:
                /* XXX sending UNT and UNL after device level read/write
                 * not supported yet, I suppose it could be since it
                 * is harmless. */
                *value = 0;
                return [m_gpib_visa_internal exit_library:boardID: NO];
                break;
            case IbaBNA:
                *value = conf->settings.board;
                return [m_gpib_visa_internal exit_library:boardID: NO];
                break;
            default:
                break;
        }
    }
    
    [m_gpib_visa_internal setIberr:EARG];
    
    return [m_gpib_visa_internal exit_library:boardID : YES];
}

-(int) ibbna:(int) boardID : (char *) board_name
{
    ibConf_t *conf;
    int retval;
    int find_index;
    
    conf = [m_gpib_visa_internal enter_library:boardID];
    if( conf == NULL )
        return [m_gpib_visa_internal exit_library:boardID : YES];
    
    if( ( find_index = [m_gpib_visa_internal ibFindDevIndex:board_name] ) < 0 )
    {
        [m_gpib_visa_internal setIberr:EARG];
        return [m_gpib_visa_internal exit_library:boardID : YES];
    }
    
    retval = [m_gpib_visa_internal my_ibbna:conf : find_index];
    if( retval < 0 )
        return [m_gpib_visa_internal exit_library:boardID : YES];
    
    return [m_gpib_visa_internal exit_library:boardID : NO];
}

-(int) ibcac:(int) boardID : (BOOL) synchronous
{
    ibConf_t *conf;
    gpib_link *board;
    gpib_link_arg* arg = [[gpib_link_arg alloc] init];
    int retval;
    
    conf = [m_gpib_visa_internal enter_library:boardID];
    if( conf == NULL )
        return [m_gpib_visa_internal exit_library:boardID : YES];
    
    if( conf->is_interface == 0 )
    {
        [m_gpib_visa_internal setIberr:EARG];
        return [m_gpib_visa_internal exit_library:boardID : YES];
    }
    
    board = [m_gpib_visa_internal interfaceBoard:conf];
    
    if( [m_gpib_visa_internal is_cic:board] == NO )
    {
        [m_gpib_visa_internal setIberr:ECIC];
        return [m_gpib_visa_internal exit_library:boardID : YES];
    }
    
    arg->cmd = IBCAC;
    arg->bTakeControl = synchronous;
    retval = [board ioctl:arg];
    //retval = ioctl( board->fileno, IBCAC, &synchronous );
    //retval = [board take_control_ioctl:synchronous];
    // if synchronous failed, fall back to asynchronous
    if( retval < 0 && synchronous  )
    {
        arg->bTakeControl = NO;
        retval = [board ioctl:arg];
    }
    if(retval < 0)
    {
        switch( errno )
        {
            default:
                [m_gpib_visa_internal setIberr:EDVR];
                break;
        }
        return [m_gpib_visa_internal exit_library:boardID : YES];
    }
    
    return [m_gpib_visa_internal exit_library:boardID : NO];
}

-(int) ibclr:(int) boardID
{
    UInt8 cmd[ 16 ];
    ibConf_t *conf;
    ssize_t count;
    int i;
    
    conf = [m_gpib_visa_internal enter_library:boardID];
    if( conf == NULL )
        return [m_gpib_visa_internal exit_library:boardID : YES];
    
    if( conf->is_interface )
    {
        [m_gpib_visa_internal setIberr:EARG];
        return [m_gpib_visa_internal exit_library:boardID : YES];
    }
    
    i = [m_gpib_visa_internal send_setup_string:conf : cmd];
    cmd[ i++ ] = SDC;
    
    //XXX detect no listeners (EBUS) error
    count = [m_gpib_visa_internal my_ibcmd:conf : cmd : i];
    if(count != i)
    {
        return [m_gpib_visa_internal exit_library:boardID : YES];
    }
    
    return [m_gpib_visa_internal exit_library:boardID : NO];
}

-(int) ibcmd:(int) boardID : (void *) cmd_buffer : (long) cnt
{
    ibConf_t *conf;
    ssize_t count;
    
    conf = [m_gpib_visa_internal enter_library:boardID];
    if( conf == NULL )
        return [m_gpib_visa_internal exit_library:boardID : YES];
    
    // check that boardID is an interface board
    if( conf->is_interface == 0 )
    {
        [m_gpib_visa_internal setIberr:EARG];
        return [m_gpib_visa_internal exit_library:boardID : YES];
    }
    
    count = [m_gpib_visa_internal my_ibcmd:conf :cmd_buffer : cnt];
    if(count < 0)
    {
        // report no listeners error XXX
        return [m_gpib_visa_internal exit_library:boardID : YES];
    }
    
    if(count != cnt)
    {
        return [m_gpib_visa_internal exit_library:boardID : YES];
    }
    
    return [m_gpib_visa_internal exit_library:boardID : NO];
}

-(int) ibcmda:(int) boardID : (void *) cmd_buffer : (long) cnt
{
    ibConf_t *conf;
    gpib_link *board;
    int retval;
    
    conf = [m_gpib_visa_internal general_enter_library:boardID : YES : NO];
    if( conf == NULL )
        return [m_gpib_visa_internal general_exit_library:boardID : YES : NO : NO : 0 : 0 : YES];
    
    // check that boardID is an interface board
    if( conf->is_interface == 0 )
    {
        [m_gpib_visa_internal setIberr:EARG];
        return [m_gpib_visa_internal general_exit_library:boardID : YES : NO : NO : 0 : 0 : YES];
    }
    
    board = [m_gpib_visa_internal interfaceBoard:conf];
    
    if( [m_gpib_visa_internal is_cic:board] == NO )
    {
        [m_gpib_visa_internal setIberr:ECIC];
        return [m_gpib_visa_internal general_exit_library:boardID : YES : NO : NO : 0 : 0 : YES];
    }
    
    retval = [m_gpib_visa_internal gpib_aio_launch:boardID : conf : GPIB_AIO_COMMAND : (void*)cmd_buffer : cnt];
    if( retval < 0 )
        return [m_gpib_visa_internal general_exit_library:boardID : YES : NO : NO : 0 : 0 : YES];
    
    return [m_gpib_visa_internal general_exit_library:boardID : NO : NO : NO : 0 : 0 : YES];
}

-(int) ibconfig:(int) boardID : (int) option : (int) value;
{
    ibConf_t *conf;
    int retval;
    
    conf = [m_gpib_visa_internal enter_library:boardID];
    if( conf == NULL )
        return [m_gpib_visa_internal exit_library:boardID : YES];
    
    switch( option )
    {
        case IbcPAD:
            retval = [m_gpib_visa_internal internal_ibpad:conf : value];
            if( retval < 0 )
                return [m_gpib_visa_internal exit_library:boardID : YES];
            return [m_gpib_visa_internal exit_library:boardID : NO];
            break;
        case IbcSAD:
            retval = [m_gpib_visa_internal internal_ibsad:conf : value];
            if( retval < 0 )
                return [m_gpib_visa_internal exit_library:boardID : YES];
            return [m_gpib_visa_internal exit_library:boardID : NO];
            break;
        case IbcTMO:
            retval = [m_gpib_visa_internal internal_ibtmo:conf : value];
            if( retval < 0 )
                return [m_gpib_visa_internal exit_library:boardID : YES];
            return [m_gpib_visa_internal exit_library:boardID : NO];
            break;
        case IbcEOT:
            [m_gpib_visa_internal internal_ibeot:conf : value];
            return [m_gpib_visa_internal exit_library:boardID : NO];
            break;
        case IbcEOSrd:
            if( value )
                conf->settings.eos_flags |= REOS;
            else
                conf->settings.eos_flags &= ~REOS;
            return [m_gpib_visa_internal exit_library:boardID : NO];
            break;
        case IbcEOSwrt:
            if( value )
                conf->settings.eos_flags |= XEOS;
            else
                conf->settings.eos_flags &= ~XEOS;
            return [m_gpib_visa_internal exit_library:boardID : NO];
            break;
        case IbcEOScmp:
            if( value )
                conf->settings.eos_flags |= BIN;
            else
                conf->settings.eos_flags &= ~BIN;
            return [m_gpib_visa_internal exit_library:boardID : NO];
            break;
        case IbcEOSchar:
            if( ( value & 0xff ) != value )
            {
                [m_gpib_visa_internal setIberr:EARG];
                return [m_gpib_visa_internal exit_library:boardID : YES];
            }
            conf->settings.eos = value;
            return [m_gpib_visa_internal exit_library:boardID : NO];
            break;
        case IbcReadAdjust:
            // XXX
            if( value )
            {
                fprintf( stderr, "libmacosx_gpib: byte swapping on reads not implemented\n");
                [m_gpib_visa_internal setIberr:ECAP];
                return [m_gpib_visa_internal exit_library:boardID : YES];
            }else
                return [m_gpib_visa_internal exit_library:boardID : NO];
            break;
        case IbcWriteAdjust:
            // XXX
            if( value )
            {
                fprintf( stderr, "libmacosx_gpib: byte swapping on writes not implemented\n");
                [m_gpib_visa_internal setIberr:ECAP];
                return [m_gpib_visa_internal exit_library:boardID : YES];
            }else
                return [m_gpib_visa_internal exit_library:boardID : NO];
            break;
        case IbcEndBitIsNormal:
            if( value )
            {
                return [m_gpib_visa_internal exit_library:boardID : NO];
            }else
            {
                fprintf( stderr, "libmacosx_gpib: no support for END on EOI only yet \n");
                [m_gpib_visa_internal setIberr:ECAP];
                return [m_gpib_visa_internal exit_library:boardID : YES];
            }
            break;
        default:
            break;
    }
    
    if( conf->is_interface )
    {
        switch( option )
        {
            case IbcPPC:
                retval = [m_gpib_visa_internal internal_ibppc:conf : value];
                if( retval < 0 )
                    return [m_gpib_visa_internal exit_library:boardID : YES];
                return [m_gpib_visa_internal exit_library:boardID : NO];
                break;
            case IbcAUTOPOLL:
                retval = [m_gpib_visa_internal configure_autospoll:conf : value];
                if( retval < 0 )
                    return [m_gpib_visa_internal exit_library:boardID : YES];
                return [m_gpib_visa_internal exit_library:boardID : NO];
                break;
            case IbcCICPROT:
                // XXX
                if( value )
                {
                    fprintf( stderr, "libmacosx_gpib: pass control protocol not supported\n");
                    [m_gpib_visa_internal setIberr:ECAP];
                    return [m_gpib_visa_internal exit_library:boardID : YES];
                }else
                    return [m_gpib_visa_internal exit_library:boardID : NO];
                break;
            case IbcIRQ:
                // XXX
                if( value == 0 )
                {
                    fprintf( stderr, "libmacosx_gpib: disabling interrupts not supported\n");
                    [m_gpib_visa_internal setIberr:ECAP];
                    return [m_gpib_visa_internal exit_library:boardID : YES];
                }else
                    return [m_gpib_visa_internal exit_library:boardID : NO];
                break;
            case IbcSC:
                retval = [m_gpib_visa_internal internal_ibrsc:conf : value];
                if( retval < 0 )
                    return [m_gpib_visa_internal exit_library:boardID : YES];
                else
                    return [m_gpib_visa_internal exit_library:boardID : NO];
                break;
            case IbcSRE:
                retval = [m_gpib_visa_internal internal_ibsre:conf : value];
                if( retval < 0 )
                    return [m_gpib_visa_internal exit_library:boardID : YES];
                return [m_gpib_visa_internal exit_library:boardID : NO];
                break;
            case IbcPP2:
                // XXX
                fprintf( stderr, "libmacosx_gpib: local/remote parallel poll configuration not implemented\n");
                [m_gpib_visa_internal setIberr:ECAP];
                return [m_gpib_visa_internal exit_library:boardID : YES];
                break;
            case IbcTIMING:
                if( [m_gpib_visa_internal set_t1_delay:[m_gpib_visa_internal interfaceBoard:conf] : value] < 0 )
                    return [m_gpib_visa_internal exit_library:boardID : YES];
                return [m_gpib_visa_internal exit_library:boardID : NO];
                break;
            case IbcDMA:
                // XXX
                if( value )
                {
                    return [m_gpib_visa_internal exit_library:boardID : NO];
                }else
                {
                    fprintf( stderr, "libmacosx_gpib: disabling DMA not supported\n");
                    [m_gpib_visa_internal setIberr:ECAP];
                    return [m_gpib_visa_internal exit_library:boardID : YES];
                }
                break;
            case IbcEventQueue:
                // XXX
                if( value )
                {
                    return [m_gpib_visa_internal exit_library:boardID : NO];
                }else
                {
                    fprintf( stderr, "libmacosx_gpib: Event Queue not supported\n");
                    [m_gpib_visa_internal setIberr:ECAP];
                    return [m_gpib_visa_internal exit_library:boardID : YES];
                }
                break;
            case IbcSPollBit:
                 // XXX
                 if( value )
                 {
                     fprintf( stderr, "libmacosx_gpib: SPOLL bit support not implemented\n");
                     [m_gpib_visa_internal setIberr:ECAP];
                     return [m_gpib_visa_internal exit_library:boardID : YES];
                 }else
                 {
                     return [m_gpib_visa_internal exit_library:boardID : NO];
                 }
                 break;
            case IbcSendLLO:
                // XXX
                if( value )
                {
                    fprintf( stderr, "libmacosx_gpib: sending local lockout on device open not implemented\n");
                    [m_gpib_visa_internal setIberr:ECAP];
                    return [m_gpib_visa_internal exit_library:boardID : YES];
                }else
                    return [m_gpib_visa_internal exit_library:boardID : NO];
                break;
            case IbcPPollTime:
                retval = [m_gpib_visa_internal set_ppoll_timeout:conf : value];
                if( retval < 0 )
                {
                    [m_gpib_visa_internal setIberr:ECAP];
                    return [m_gpib_visa_internal exit_library:boardID : YES];
                }else
                {
                    return [m_gpib_visa_internal exit_library:boardID : NO];
                }
                break;
            case IbcHSCableLength:
                // XXX
                if( value )
                {
                    fprintf( stderr, "libmacosx_gpib: HS protocol not supported\n" );
                    [m_gpib_visa_internal setIberr:ECAP];
                    return [m_gpib_visa_internal exit_library:boardID : YES];
                }else
                    return [m_gpib_visa_internal exit_library:boardID : NO];
                break;
            case IbcIst:
                retval = [m_gpib_visa_internal internal_ibist:conf : value];
                if( retval < 0 )
                    return [m_gpib_visa_internal exit_library:boardID : YES];
                else
                    return [m_gpib_visa_internal exit_library:boardID : NO];
                break;
            case IbcRsv:
                retval = [m_gpib_visa_internal internal_ibrsv:conf : value];
                if( retval < 0 )
                    return [m_gpib_visa_internal exit_library:boardID : YES];
                else
                    return [m_gpib_visa_internal exit_library:boardID : NO];
                break;
            default:
                break;
        }
    }else
    {
        switch( option )
        {
            case IbcREADDR:
                /* We always re-address.  To support only
                 * readdressing when necessary would require
                 * making the driver keep track of current addressing
                 * state.  Maybe someday, but low priority. */
                if( value )
                    conf->settings.readdr = 1;
                else
                    conf->settings.readdr = 0;
                return [m_gpib_visa_internal exit_library:boardID : NO];
                break;
            case IbcSPollTime:
                retval = [m_gpib_visa_internal set_spoll_timeout:conf : value];
                if( retval < 0 )
                {
                    [m_gpib_visa_internal setIberr:EARG];
                    return [m_gpib_visa_internal exit_library:boardID : YES];
                }else
                {
                    return [m_gpib_visa_internal exit_library:boardID : NO];
                }
                break;
            case IbcUnAddr:
                // XXX
                if( value )
                {
                    fprintf( stderr, "libmacosx_gpib: no support for UNT/UNL at end of "
                            "device read and writes\n" );
                    [m_gpib_visa_internal setIberr:ECAP];
                    return [m_gpib_visa_internal exit_library:boardID : YES];
                }else
                    return [m_gpib_visa_internal exit_library:boardID : NO];
                break;
            case IbcBNA:
                retval = [m_gpib_visa_internal my_ibbna:conf : value];
                if( retval < 0 )
                    return [m_gpib_visa_internal exit_library:boardID : YES];
                else
                    return [m_gpib_visa_internal exit_library:boardID : NO];
                break;
            default:
                break;
        }
    }
    
    [m_gpib_visa_internal setIberr:EARG];
    return [m_gpib_visa_internal exit_library:boardID : YES];
}

-(int) ibdev:(int) board_index : (int) pad : (int) sad : (int) timo : (BOOL) send_eoi : (int) eosmode
{
    ibConf_t *new_conf = [[ibConf_t alloc] init];
    sad -= sad_offset;
    
    [m_gpib_visa_internal init_ibconf:new_conf];
    new_conf->settings.pad = pad;
    new_conf->settings.sad = sad;                        /* device address                   */
    new_conf->settings.board = board_index;                         /* board number                     */
    new_conf->settings.eos = eosmode & 0xff;                           /* local eos modes                  */
    new_conf->settings.eos_flags = eosmode & 0xff00;
    new_conf->settings.usec_timeout = [m_gpib_visa_internal timeout_to_usec:timo];
    if( send_eoi )
        new_conf->settings.send_eoi = YES;
    else
        new_conf->settings.send_eoi = NO;
    new_conf->defaults = new_conf->settings;
    new_conf->is_interface = 0;
    
    return [m_gpib_visa_internal my_ibdev:new_conf];
    // XXX check for address conflicts with boards
}

-(int) ibeot:(int) boardID : (BOOL) send_eoi
{
    ibConf_t *conf;
    
    conf = [m_gpib_visa_internal general_enter_library:boardID : YES : NO];
    if( conf == NULL )
        return [m_gpib_visa_internal general_exit_library:boardID : YES : NO : NO : 0 : 0 : YES];
    
    [m_gpib_visa_internal internal_ibeot:conf : send_eoi];
    
    return [m_gpib_visa_internal general_exit_library:boardID : NO : NO : NO : 0 : 0 : YES];
}

-(int) ibeos:(int) boardID : (int) v
{
    ibConf_t *conf;
    
    conf = [m_gpib_visa_internal general_enter_library:boardID : YES : NO];
    if( conf == NULL )
        return [m_gpib_visa_internal general_exit_library:boardID : YES : NO : NO : 0 : 0 : YES];
    
    conf->settings.eos = v & 0xff;
    conf->settings.eos_flags = v & 0xff00;
    
    return [m_gpib_visa_internal general_exit_library:boardID : NO : NO : NO : 0 : 0 : YES];
}

-(int) ibfind:(const char *) name
{
    return [m_gpib_visa_internal findBoardWithName:name];
}

-(int) ibcount
{
    return [m_gpib_visa_internal boardCount];
}

-(const char*) ibname:(int) boardID
{
    return [m_gpib_visa_internal ibBoardName:boardID];
}

// incomplete XXX need to implement acceptor handshake stuff in drivers
-(int) ibgts:(int) boardID : (int) shadow_handshake
{
    ibConf_t *conf;
    int retval;
    
    conf = [m_gpib_visa_internal enter_library:boardID];
    if( conf == NULL )
        return [m_gpib_visa_internal exit_library:boardID : YES];
    
    if( conf->is_interface == 0 )
    {
        [m_gpib_visa_internal setIberr:EARG];
        return [m_gpib_visa_internal exit_library:boardID : YES];
    }
    
    retval = [m_gpib_visa_internal internal_ibgts:conf : shadow_handshake];
    if( retval < 0 )
    {
        return [m_gpib_visa_internal exit_library:boardID : YES];
    }
    
    return [m_gpib_visa_internal exit_library:boardID : NO];
}

-(int) ibist:(int) boardID : (int) ist
{
    ibConf_t *conf;
    int retval;
    
    conf = [m_gpib_visa_internal enter_library:boardID];
    if( conf == NULL )
        return [m_gpib_visa_internal exit_library:boardID : YES];
    
    retval = [m_gpib_visa_internal internal_ibist:conf : ist];
    if( retval < 0 )
        return [m_gpib_visa_internal exit_library:boardID : YES];
    
    return [m_gpib_visa_internal exit_library:boardID : NO];
}

-(int) iblines:(int) boardID : (short *) line_status
{
    ibConf_t *conf;
    int retval;
    
    conf = [m_gpib_visa_internal general_enter_library:boardID : YES : YES];
    if( conf == NULL )
        return [m_gpib_visa_internal general_exit_library:boardID : YES : NO : NO : 0 : 0 : YES];
    
    retval = [m_gpib_visa_internal internal_iblines:conf : line_status];
    if( retval < 0 )
    {
        return [m_gpib_visa_internal general_exit_library:boardID : YES : NO : NO : 0 : 0 : YES];
    }
    
    return [m_gpib_visa_internal general_exit_library:boardID : NO : NO : NO : 0 : 0 : YES];
}

-(int) ibln:(int) boardID : (int) pad : (int) sad : (short *) found_listener;
{
    ibConf_t *conf;
    uint16_t addressList[ 2 ];
    int retval;
    
    conf = [m_gpib_visa_internal enter_library:boardID];
    if( conf == NULL )
        return [m_gpib_visa_internal exit_library:boardID : YES];
    
    switch( sad )
    {
        case ALL_SAD:
            retval = [m_gpib_visa_internal secondaryListenerFound:conf : pad];
            break;
        case NO_SAD:
        default:
            addressList[ 0 ] = [gpib_visa_internal MakeAddr:pad : sad];
            addressList[ 1 ] = NOADDR;
            retval = [m_gpib_visa_internal listenerFound:conf : addressList];
            break;
    }
    if( retval < 0 )
        return [m_gpib_visa_internal exit_library:boardID : YES];
    
    *found_listener = retval;
    
    return [m_gpib_visa_internal exit_library:boardID : NO];
}

-(int) ibloc:(int) boardID
{
    ibConf_t *conf;
    gpib_link *board;
    gpib_link_arg* arg = [[gpib_link_arg alloc] init];

    UInt8 cmd[32];
    int i;
    ssize_t count;
    int retval;
    conf = [m_gpib_visa_internal general_enter_library:boardID : YES : YES];
    if( conf == NULL )
        return [m_gpib_visa_internal exit_library:boardID : YES];
    
    board = [m_gpib_visa_internal interfaceBoard:conf];
    
    if( conf->is_interface )
    {
        //retval = ioctl( board->fileno, IBLOC );
        arg->cmd = IBLOC;
        retval = [board ioctl:arg];
        if( retval < 0 )
        {
            fprintf( stderr, "IBLOC ioctl failed\n" );
            [m_gpib_visa_internal setIberr:EDVR];
            [m_gpib_visa_internal setIbcnt:errno];
            return [m_gpib_visa_internal exit_library:boardID : YES];
        }
    }else
    {
        retval = [m_gpib_visa_internal conf_lock_board:conf];
        if( retval < 0 )
        {
            return [m_gpib_visa_internal general_exit_library:boardID : YES : NO : NO : 0 : 0 : YES];
        }
        i = [m_gpib_visa_internal send_setup_string:conf : cmd];
        if( i < 0 )
        {
            [m_gpib_visa_internal setIberr:EDVR];
            return [m_gpib_visa_internal exit_library:boardID : YES];
        }
        cmd[ i++ ] = GTL;
        count = [m_gpib_visa_internal my_ibcmd:conf : cmd : i];
        if(count != i)
        {
            return [m_gpib_visa_internal exit_library:boardID : YES];
        }
    }
    
    return [m_gpib_visa_internal exit_library:boardID : NO];
}

-(int) ibonl:(int) boardID : (BOOL) onl
{
    ibConf_t *conf;
    int retval;
    int status;
    
    if( boardID > GPIB_MAX_NUM_BOARDS )
    {
        return -1;
    }
    
    conf = [m_gpib_visa_internal general_enter_library:boardID : YES : YES];
    if( conf == NULL )
        return [m_gpib_visa_internal general_exit_library:boardID : YES : NO : NO : 0 : 0 : YES];
    
    retval = [m_gpib_visa_internal internal_ibstop:conf];
    if( retval < 0 )
        return [m_gpib_visa_internal general_exit_library:boardID : YES : NO : NO : 0 : 0 : YES];
    
    retval = [m_gpib_visa_internal conf_lock_board:conf];
    if( retval < 0 )
        return [m_gpib_visa_internal general_exit_library:boardID : YES : NO : NO : 0 : 0 : YES];
    
    if( onl == YES)
    {
        retval = [m_gpib_visa_internal reinit_descriptor:conf];
        if( retval < 0 )
            return [m_gpib_visa_internal exit_library:boardID : YES];
        else
            return [m_gpib_visa_internal exit_library:boardID : NO];
    }
    
    status = [m_gpib_visa_internal general_exit_library:boardID : NO : NO : NO : 0 : CMPL : YES];
    
    if( onl == 0 )
        retval = [m_gpib_visa_internal close_gpib_handle:conf];
    else
        retval = 0;
    [m_gpib_visa_internal conf_unlock_board:conf];
    if( retval < 0 )
    {
        fprintf( stderr, "libmacosx_gpib: failed to mark device as closed!\n" );
        [m_gpib_visa_internal setIberr:EDVR];
        [m_gpib_visa_internal setIbcnt:errno];
        status |= ERR;
        [m_gpib_visa_internal setIbsta:status];
        [m_gpib_visa_internal sync_globals];
        return status;
    }
    return status;
}

-(int) ibpad:(int) boardID : (int) address
{
    ibConf_t *conf;
    int retval;
    
    conf = [m_gpib_visa_internal enter_library:boardID];
    if( conf == NULL )
        return [m_gpib_visa_internal exit_library:boardID: YES];
    
    retval = [m_gpib_visa_internal internal_ibpad:conf : address];
    if( retval < 0 )
    {
        return [m_gpib_visa_internal exit_library:boardID: YES];
    }
    
    return [m_gpib_visa_internal exit_library:boardID: NO];
}

-(int) ibpct:(int) boardID
{
    ibConf_t *conf;
    int retval;
    
    conf = [m_gpib_visa_internal enter_library:boardID];
    if( conf == NULL )
        return [m_gpib_visa_internal exit_library:boardID : YES];
    
    if( conf->is_interface )
    {
        [m_gpib_visa_internal setIberr:EARG];
        return [m_gpib_visa_internal exit_library:boardID : YES];
    }
    
    retval = [m_gpib_visa_internal my_pass_control:conf : conf->settings.pad : conf->settings.sad];
    if( retval < 0 )
        return [m_gpib_visa_internal exit_library:boardID: YES];
    
    return [m_gpib_visa_internal exit_library:boardID: NO];
}

-(int) ibppc:(int) boardID : (int) v
{
    ibConf_t *conf;
    int retval;
    
    conf = [m_gpib_visa_internal enter_library:boardID];
    if( conf == NULL )
        return [m_gpib_visa_internal exit_library:boardID : YES];
    
    retval = [m_gpib_visa_internal internal_ibppc:conf : v];
    if( retval < 0 )
        return [m_gpib_visa_internal exit_library:boardID : YES];
    
    return [m_gpib_visa_internal exit_library:boardID : NO];
}

-(int) ibrd:(int) boardID : (void *) buf : (long) count
{
    ibConf_t *conf;
    ssize_t retval;
    size_t bytes_read;
    
    conf = [m_gpib_visa_internal enter_library:boardID];
    if( conf == NULL )
        return [m_gpib_visa_internal exit_library:boardID : YES];
    
    retval = [m_gpib_visa_internal my_ibrd:conf : buf : count : &bytes_read];

    if(retval < 0)
    {
        if([m_gpib_visa_internal ThreadIberr] != EDVR)
            [m_gpib_visa_internal setIbcnt:bytes_read];
        return [m_gpib_visa_internal exit_library:boardID : YES];
    }else
    {
        [m_gpib_visa_internal setIbcnt:bytes_read];
    }
    
    return [m_gpib_visa_internal general_exit_library:boardID : NO : NO : NO : DCAS : 0 : NO];
}

-(int) ibrda:(int) boardID : (void *) buf : (long) count
{
    ibConf_t *conf;
    int retval;
    
    conf = [m_gpib_visa_internal general_enter_library:boardID : YES : NO];
    if( conf == NULL )
        return [m_gpib_visa_internal general_exit_library:boardID : YES : NO : NO : 0 : 0 : YES];
    
    retval = [m_gpib_visa_internal gpib_aio_launch:boardID : conf : GPIB_AIO_READ : buf : count];
    if( retval < 0 )
        return [m_gpib_visa_internal general_exit_library:boardID : YES : NO : NO : 0 : 0 : YES];
    
    return [m_gpib_visa_internal general_exit_library:boardID : NO : NO : NO : 0 : 0 : YES];
}

-(int) ibrdf:(int) boardID : (char *) file_path
{
    ibConf_t *conf;
    int retval;
    UInt8 buffer[ 0x4000 ];
    unsigned long byte_count;
    FILE *save_file;
    BOOL error;
    
    conf = [m_gpib_visa_internal enter_library:boardID];
    if( conf == NULL )
        return [m_gpib_visa_internal exit_library:boardID : YES];
    
    save_file = fopen( file_path, "a" );
    if( save_file == NULL )
    {
        [m_gpib_visa_internal setIberr:EFSO];
        [m_gpib_visa_internal setIbcnt:errno];
        return [m_gpib_visa_internal exit_library:boardID : YES];
    }
    
    if( conf->is_interface == 0 )
    {
        // set up addressing
        if( [m_gpib_visa_internal InternalReceiveSetup:conf : [m_gpib_visa_internal packAddress: conf->settings.pad : conf->settings.sad]] < 0 )
        {
            return [m_gpib_visa_internal exit_library:boardID : YES];
        }
    }
    
    // set eos mode
    [m_gpib_visa_internal iblcleos:conf];
    
    byte_count = error = 0;
    do
    {
        int fwrite_count;
        size_t bytes_read;
        
        retval = (int)[m_gpib_visa_internal read_data:conf : buffer : sizeof(buffer) : &bytes_read];
        fwrite_count = (int)fwrite( buffer, 1, bytes_read, save_file );
        if( fwrite_count != bytes_read )
        {
            [m_gpib_visa_internal setIberr:EFSO];
            [m_gpib_visa_internal setIbcnt:errno];
            error++;
        }
        byte_count += fwrite_count;
        if( retval < 0 )
        {
            error++;
            break;
        }
    }while( conf->end == 0 && error == 0 );
    
    [m_gpib_visa_internal setIbcnt:byte_count];
    
    if( fclose( save_file ) )
    {
        [m_gpib_visa_internal setIberr:EFSO];
        [m_gpib_visa_internal setIbcnt:errno];
        return [m_gpib_visa_internal exit_library:boardID : YES];
    }
    if( error )
        return [m_gpib_visa_internal exit_library:boardID : error];
    
    return [m_gpib_visa_internal general_exit_library:boardID : NO : NO : NO : DCAS : 0 : NO];

}

-(int) ibrpp:(int) boardID : (char *) ppr
{
    ibConf_t *conf;
    int retval;
    
    conf = [m_gpib_visa_internal enter_library:boardID];
    if( conf == NULL )
        return [m_gpib_visa_internal exit_library:boardID : YES];
    
    retval = [m_gpib_visa_internal internal_ibrpp:conf : ppr];
    if( retval < 0 )
    {
        return [m_gpib_visa_internal exit_library:boardID : YES];
    }
    
    return [m_gpib_visa_internal exit_library:boardID : NO];
}

-(int) ibrsc:(int) boardID : (BOOL) request_control
{
    ibConf_t *conf;
    int retval;
    
    conf = [m_gpib_visa_internal enter_library:boardID];
    if( conf == NULL )
        return [m_gpib_visa_internal exit_library:boardID : YES];
    
    retval = [m_gpib_visa_internal internal_ibrsc:conf : request_control];
    if( retval < 0 )
    {
        return [m_gpib_visa_internal exit_library:boardID : YES];
    }
    
    return [m_gpib_visa_internal exit_library:boardID : NO];
}

-(int) ibrsp:(int) boardID : (UInt8 *) spr
{
    ibConf_t *conf;
    gpib_link *board;
    int retval;
    
    conf = [m_gpib_visa_internal enter_library:boardID];
    if( conf == NULL )
        return [m_gpib_visa_internal exit_library:boardID : YES];
    
    if( conf->is_interface )
    {
        [m_gpib_visa_internal setIberr:EARG];
        return [m_gpib_visa_internal exit_library:boardID : YES];
    }
    board = [m_gpib_visa_internal interfaceBoard:conf];
    retval = [m_gpib_visa_internal serial_poll:board : conf->settings.pad : conf->settings.sad : conf->settings.spoll_usec_timeout : spr];
    if(retval < 0)
    {
        if( errno == ETIMEDOUT )
            conf->timed_out = 1;
        return [m_gpib_visa_internal exit_library:boardID : YES];
    }
    
    return [m_gpib_visa_internal exit_library:boardID : NO];
}

// should return old status byte in iberr on success
-(int) ibrsv:(int) boardID : (int) v
{
    ibConf_t *conf;
    int retval;
    
    conf = [m_gpib_visa_internal enter_library:boardID];
    if( conf == NULL )
        return [m_gpib_visa_internal exit_library:boardID : YES];
    
    retval = [m_gpib_visa_internal internal_ibrsv:conf : v];
    if( retval < 0 )
    {
        return [m_gpib_visa_internal exit_library:boardID : YES];
    }
    
    return [m_gpib_visa_internal exit_library:boardID : NO];
}

-(int) ibsad:(int) boardID : (int) address
{
    ibConf_t *conf;
    int retval;
    
    conf = [m_gpib_visa_internal enter_library:boardID];
    if( conf == NULL )
        return [m_gpib_visa_internal exit_library:boardID : YES];
    
    retval = [m_gpib_visa_internal internal_ibsad:conf : address];
    if( retval < 0 )
    {
        return [m_gpib_visa_internal exit_library:boardID : YES];
    }
    
    return [m_gpib_visa_internal exit_library:boardID : NO];
}

-(int) ibsic:(int) boardID
{
    ibConf_t *conf;
    int retval;
    
    conf = [m_gpib_visa_internal enter_library:boardID];
    if( conf == NULL )
        return [m_gpib_visa_internal exit_library:boardID : YES];
    
    retval = [m_gpib_visa_internal internal_ibsic:conf];
    if( retval < 0 )
    {
        return [m_gpib_visa_internal exit_library:boardID : YES];
    }
    
    return [m_gpib_visa_internal exit_library: boardID : NO];
}

-(int) ibsre:(int) boardID : (BOOL) enable
{
    ibConf_t *conf;
    int retval;
    
    conf = [m_gpib_visa_internal enter_library:boardID];
    if( conf == NULL )
        return [m_gpib_visa_internal exit_library:boardID : YES];
    
    retval = [m_gpib_visa_internal internal_ibsre:conf : enable];
    if( retval < 0 )
    {
        fprintf( stderr, "libmacosx_gpib: ibsre error\n");
        return [m_gpib_visa_internal exit_library:boardID : YES];
    }
    //XXX supposed to set iberr to old REN setting
    return [m_gpib_visa_internal exit_library:boardID : NO];
}

-(int) ibstop:(int) boardID
{
    ibConf_t *conf;
    int retval;
    
    conf = [m_gpib_visa_internal general_enter_library:boardID : YES : YES];
    if( conf == NULL )
        return [m_gpib_visa_internal general_exit_library:boardID : YES : NO : NO : 0 : 0 : YES];
    
    retval = [m_gpib_visa_internal internal_ibstop:conf];
    if( retval < 0 )
        return [m_gpib_visa_internal general_exit_library:boardID : YES : NO : NO : 0 : 0 : YES];
    
    return [m_gpib_visa_internal general_exit_library:boardID : NO : NO : NO : 0 : CMPL : YES];
}

-(int) ibtmo:(int) boardID : (int) timeout
{
    ibConf_t *conf;
    int retval;
    
    conf = [m_gpib_visa_internal general_enter_library:boardID : YES : NO];
    if( conf == NULL )
        return [m_gpib_visa_internal general_exit_library:boardID : YES : NO : NO : 0 : 0 : YES];
    
    retval = [m_gpib_visa_internal internal_ibtmo:conf : timeout];
    if( retval < 0 )
    {
        return [m_gpib_visa_internal general_exit_library:boardID : YES : NO : NO : 0 : 0 : YES];
    }
    
    return [m_gpib_visa_internal general_exit_library:boardID : NO : NO : NO : 0 : 0 : YES];
}

-(int) ibtrg:(int) boardID
{
    ibConf_t *conf;
    int retval;
    uint16_t addressList[ 2 ];
    
    conf = [m_gpib_visa_internal enter_library:boardID];
    if( conf == NULL )
        return [m_gpib_visa_internal exit_library:boardID : YES];
    
    if( conf->is_interface )
    {
        [m_gpib_visa_internal setIberr:EARG];
        return [m_gpib_visa_internal exit_library:boardID: YES];
    }
    
    addressList[ 0 ] = [m_gpib_visa_internal packAddress:conf->settings.pad : conf->settings.sad];
    addressList[ 1 ] = NOADDR;
    
    retval = [m_gpib_visa_internal my_trigger:conf : addressList];
    if( retval < 0 )
    {
        return [m_gpib_visa_internal exit_library:boardID: YES];
    }
    
    return [m_gpib_visa_internal exit_library:boardID: NO];
}

-(const char*) ibvers
{
    return GPIB_SCM_VERSION;
}

-(int) ibwait:(int) boardID : (int) mask
{
    ibConf_t *conf;
    int retval;
    int status;
    int clear_mask;
    int error = 0;
    
    conf = [m_gpib_visa_internal general_enter_library:boardID: YES : NO];
    if( conf == NULL )
        return [m_gpib_visa_internal general_exit_library:boardID : YES : NO : NO : 0 : 0 : YES];
    
    clear_mask = mask & ( DTAS | DCAS | SPOLL);
    retval = [m_gpib_visa_internal my_wait:conf : mask : clear_mask : 0 : &status];
    if( retval < 0 )
        return [m_gpib_visa_internal general_exit_library:boardID : YES : NO : NO : 0 : 0 : YES];
    
    //XXX
    if(conf->async->in_progress && (status & CMPL))
    {
        pthread_mutex_lock( &conf->async->lock );
        if( conf->async->ibsta & CMPL )
        {
            conf->async->in_progress = 0;
            [m_gpib_visa_internal setIbcnt:conf->async->ibcntl];
            [m_gpib_visa_internal setIberr:conf->async->iberr];
            if( conf->async->ibsta & ERR )
            {
                error++;
            }
        }
        pthread_mutex_unlock( &conf->async->lock );
        if(error && ([m_gpib_visa_internal ThreadIbsta] & ERR) == 0)
        {
            status |= ERR;
            [m_gpib_visa_internal setIbsta:status];
        }
    }
    
    [m_gpib_visa_internal general_exit_library:boardID : error : 0 : YES : 0 : 0 : YES];
    
    return status;
}

-(int) ibwrt:(int) boardID : (void *) buffer : (long) count
{
    ibConf_t *conf;
    size_t scount;
    int retval;
    
    conf = [m_gpib_visa_internal enter_library:boardID];
    if( conf == NULL )
        return [m_gpib_visa_internal exit_library:boardID : YES];
    
    conf->end = 0;
    
    retval = [m_gpib_visa_internal my_ibwrt:conf : buffer : count : &scount];
    if(retval < 0)
    {
        if([m_gpib_visa_internal ThreadIberr] != EDVR)
            [m_gpib_visa_internal setIbcnt:count];
        return [m_gpib_visa_internal exit_library:boardID : YES];
    }
    [m_gpib_visa_internal setIbcnt:count];
    return [m_gpib_visa_internal general_exit_library:boardID : NO : NO : NO : DCAS : 0 : NO];
}

-(int) ibwrta:(int) boardID : (void *) buffer : (long) count
{
    ibConf_t *conf;
    int retval;
    
    conf = [m_gpib_visa_internal general_enter_library:boardID : YES : NO];
    if( conf == NULL )
        return [m_gpib_visa_internal general_exit_library:boardID : YES : NO : NO : 0 : 0 : YES];
    
    retval = [m_gpib_visa_internal gpib_aio_launch:boardID : conf : GPIB_AIO_WRITE : (void*)buffer : count];
    if( retval < 0 )
        return [m_gpib_visa_internal general_exit_library:boardID : YES : NO : NO : 0 : 0 : YES];
    
    return [m_gpib_visa_internal general_exit_library:boardID : NO : NO : NO : 0 : 0 : YES];
}

-(int) ibwrtf:(int) boardID : (char *) file_path
{
    ibConf_t *conf;
    size_t count;
    int retval;
    
    conf = [m_gpib_visa_internal enter_library:boardID];
    if( conf == NULL )
        return [m_gpib_visa_internal exit_library:boardID: YES];
    
    conf->end = 0;
    
    retval = [m_gpib_visa_internal my_ibwrtf:conf : file_path : &count];
    if(retval < 0)
    {
        if([m_gpib_visa_internal ThreadIberr] != EDVR)
            [m_gpib_visa_internal setIbcnt:count];
        return [m_gpib_visa_internal exit_library:boardID: YES];
    }
    [m_gpib_visa_internal setIbcnt:count];
    
    return [m_gpib_visa_internal general_exit_library:boardID: NO : NO : NO : DCAS : 0 : NO];
}

-(int) ibspb:(int) boardID : (short *) sp_bytes
{
    ibConf_t *conf;
    int retval;
    
    conf = [m_gpib_visa_internal enter_library:boardID];
    if( conf == NULL )
        return [m_gpib_visa_internal exit_library:boardID: YES];
    
    conf->end = 0;
    
    //retval = [m_gpib_visa_internal my_ibspb:conf : sp_bytes ];
    //FIXME just hardcode it to 0 for now
    *sp_bytes =0;
    if(retval < 0)
    {
        return [m_gpib_visa_internal exit_library:boardID: YES];
    }
    
    return [m_gpib_visa_internal general_exit_library:boardID: NO : NO : NO : DCAS : 0 : NO];
}

-(const char*) gpib_error_string:(int) error
{
    static const int max_error_code = ETAB;
    
    if( error < 0 || error > max_error_code )
        return "libmacosx_gpib: Unknown error code";
    
    return error_descriptions[ error ];
}

-(void) setIbsta:(int) status
{
    [m_gpib_visa_internal setIbsta:status];
}
-(void) setIberr:(int) error
{
    [m_gpib_visa_internal setIberr:error];
}
-(void) setIbcnt:(long) count
{
    [m_gpib_visa_internal setIbcnt:count];
}
-(int) ThreadIbsta
{
    return [m_gpib_visa_internal ThreadIbsta];
}
-(int) ThreadIberr
{
    return [m_gpib_visa_internal ThreadIberr];
}
-(int) ThreadIbcnt
{
    return [m_gpib_visa_internal ThreadIbcnt];
}


@end
