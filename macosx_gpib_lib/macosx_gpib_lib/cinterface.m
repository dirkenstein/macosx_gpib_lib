#import "gpib_visa.h"
//#include <gpib/ni4882.h>
#include "ib.h"
volatile int ibsta;
volatile int iberr;
volatile int ibcnt;
volatile long ibcntl;
static gpib_visa * gvisa = NULL;

void ibinit (void) {
  if (!gvisa) gvisa = [[gpib_visa alloc] init];
}

int ibconfig (int ud, int option, int v) {
    ibinit();
    unsigned int res =  [gvisa ibconfig:ud:option:v];
	ibsta = [gvisa ThreadIbsta];
	iberr = [gvisa ThreadIberr];
	ibcnt = ibcntl = [gvisa ThreadIbcnt];
	return res;
}

void FindLstn(int boardID, const Addr4882_t addrlist[], Addr4882_t * results, int limit){
    ibinit();
    [gvisa FindLstn:boardID:addrlist:results:limit];
    ibsta = [gvisa ThreadIbsta];
    iberr = [gvisa ThreadIberr];
    ibcnt = ibcntl = [gvisa ThreadIbcnt];
};

void Receive(int boardID, Addr4882_t addr, void * buffer, long cnt, int Termination){
    ibinit();
    [gvisa Receive:boardID:addr:buffer:cnt:Termination];
    ibsta = [gvisa ThreadIbsta];
    iberr = [gvisa ThreadIberr];
    ibcnt = ibcntl = [gvisa ThreadIbcnt];
};
void Send(int boardID, Addr4882_t addr, const void * databuf, long datacnt, int eotMode) {
    ibinit();
    [gvisa Send:boardID:addr:databuf:datacnt:eotMode];
    ibsta = [gvisa ThreadIbsta];
    iberr = [gvisa ThreadIberr];
    ibcnt = ibcntl = [gvisa ThreadIbcnt];
};
void SendIFC        (int boardID) {
    ibinit();
    [gvisa SendIFC:boardID];
    ibsta = [gvisa ThreadIbsta];
    iberr = [gvisa ThreadIberr];
    ibcnt = ibcntl = [gvisa ThreadIbcnt];
};
int ibask    (int ud, int option, int * v) {
    ibinit();
    unsigned int res = [gvisa ibask:ud:option:v];
	ibsta = [gvisa ThreadIbsta];
	iberr = [gvisa ThreadIberr];
	ibcnt = ibcntl = [gvisa ThreadIbcnt];
	return res;
};
int ibclr    (int ud){
    ibinit();
	unsigned int res = [gvisa ibclr:ud];
	ibsta = [gvisa ThreadIbsta];
	iberr = [gvisa ThreadIberr];
	ibcnt = ibcntl = [gvisa ThreadIbcnt];
	return res;
};
int ibpct    (int ud){
    ibinit();
	unsigned int res = [gvisa ibpct:ud];
	ibsta = [gvisa ThreadIbsta];
	iberr = [gvisa ThreadIberr];
	ibcnt = ibcntl = [gvisa ThreadIbcnt];
	return res;
};
int   ibdev   (int boardID, int pad, int sad, int tmo, int eot, int eos){
    ibinit();
	int res =  [gvisa ibdev:boardID:pad:sad:tmo:eot:eos];
	ibsta = [gvisa ThreadIbsta];
	iberr = [gvisa ThreadIberr];
	ibcnt = ibcntl = [gvisa ThreadIbcnt];
	return res;
};
int ibonl (int ud, int v){
    ibinit();
	unsigned int res =  [gvisa ibonl:ud:v];
	ibsta = [gvisa ThreadIbsta];
	iberr = [gvisa ThreadIberr];
	ibcnt = ibcntl = [gvisa ThreadIbcnt];
	return res;
};

int ibcac (int ud, int sync) {
    ibinit();
    unsigned int res =  [gvisa ibcac:ud:sync];
	ibsta = [gvisa ThreadIbsta];
	iberr = [gvisa ThreadIberr];
	ibcnt = ibcntl = [gvisa ThreadIbcnt];
	return res;
}
int ibgts (int ud, int shadow) {
    ibinit();
    unsigned int res =  [gvisa ibgts:ud:shadow];
	ibsta = [gvisa ThreadIbsta];
	iberr = [gvisa ThreadIberr];
	ibcnt = ibcntl = [gvisa ThreadIbcnt];
	return res;
}
int ibsre (int ud, int v) {
    ibinit();
	unsigned int res =  [gvisa ibsre:ud:v];
	ibsta = [gvisa ThreadIbsta];
	iberr = [gvisa ThreadIberr];
	ibcnt = ibcntl = [gvisa ThreadIbcnt];
	return res;
};

int ibtmo (int ud, int v) {
    ibinit();
	unsigned int res =  [gvisa ibtmo:ud:v];
	ibsta = [gvisa ThreadIbsta];
	iberr = [gvisa ThreadIberr];
	ibcnt = ibcntl = [gvisa ThreadIbcnt];
	return res;
};

int ibrd     (int ud, void * buf, long cnt){
    ibinit();
	unsigned int res =  [gvisa ibrd:ud:buf:cnt];
	ibsta = [gvisa ThreadIbsta];
	iberr = [gvisa ThreadIberr];
    ibcnt = ibcntl = [gvisa ThreadIbcnt];
	return res;
};
int ibrsp    (int ud, char * spr){
    ibinit();
	unsigned int res =  [gvisa ibrsp:ud:spr];
	ibsta = [gvisa ThreadIbsta];
	iberr = [gvisa ThreadIberr];
	ibcnt = ibcntl =  [gvisa ThreadIbcnt];
	return res;
};
int ibsic    (int ud){
    ibinit();
	unsigned int res =  [gvisa ibsic:ud];
	ibsta = [gvisa ThreadIbsta];
	iberr = [gvisa ThreadIberr];
	ibcnt = ibcntl =  [gvisa ThreadIbcnt];
	return res;
};
int ibwrt    (int ud, const void * buf, long cnt){
    ibinit();
	unsigned int res =  [gvisa ibwrt:ud:buf:cnt];
	ibsta = [gvisa ThreadIbsta];
	iberr = [gvisa ThreadIberr];
	ibcnt =  ibcntl = [gvisa ThreadIbcnt];
	return res;
};
int  ibcmd    (int ud, const void * buf, long cnt) {
    ibinit();
	unsigned int res =  [gvisa ibcmda:ud:buf:cnt];
	ibsta = [gvisa ThreadIbsta];
	iberr = [gvisa ThreadIberr];
	ibcnt =  ibcntl = [gvisa ThreadIbcnt];
	return res;
};

int  ibcmda   (int ud, const void * buf, long cnt) {
    ibinit();
	unsigned int res =  [gvisa ibcmd:ud:buf:cnt];
	ibsta = [gvisa ThreadIbsta];
	iberr = [gvisa ThreadIberr];
	ibcnt =  ibcntl = [gvisa ThreadIbcnt];
	return res;
};
int ibln     (int ud, int pad, int sad, short * listen) {
    ibinit();
	unsigned int res =  [gvisa ibln:ud:pad:sad:listen];
	ibsta = [gvisa ThreadIbsta];
	iberr = [gvisa ThreadIberr];
	ibcnt =  ibcntl = [gvisa ThreadIbcnt];
	return res;
};
int iblines     (int ud, short * status) {
    ibinit();
	unsigned int res =  [gvisa iblines:ud:status];
	ibsta = [gvisa ThreadIbsta];
	iberr = [gvisa ThreadIberr];
	ibcnt =  ibcntl = [gvisa ThreadIbcnt];
	return res;
};
int  ibloc    (int ud) {
    ibinit();
	unsigned int res =  [gvisa ibloc:ud];
	ibsta = [gvisa ThreadIbsta];
	iberr = [gvisa ThreadIberr];
	ibcnt =  ibcntl = [gvisa ThreadIbcnt];
	return res;
};
int ibtrg    (int ud) {
    ibinit();
	unsigned int res =  [gvisa ibtrg:ud];
	ibsta = [gvisa ThreadIbsta];
	iberr = [gvisa ThreadIberr];
	ibcnt =  ibcntl = [gvisa ThreadIbcnt];
	return res;
};

int ibwait   (int ud, int mask) {
    ibinit();
	unsigned int res =  [gvisa ibwait:ud:mask];
	ibsta = [gvisa ThreadIbsta];
	iberr = [gvisa ThreadIberr];
	ibcnt =  ibcntl = [gvisa ThreadIbcnt];
	return res;
};
int ibwrta   (int ud, const void * buf, long cnt) {
	unsigned int res =  [gvisa ibwrta:ud:buf:cnt];
	ibsta = [gvisa ThreadIbsta];
	iberr = [gvisa ThreadIberr];
	ibcnt =  ibcntl = [gvisa ThreadIbcnt];
	return res;
};
void ibvers( char **version) {
    ibinit();
	*version = "mcosx_gpib_lib_3.0.1a";
};
int  ibfind  (const char * udname) {
    ibinit();
	unsigned int res =  [gvisa ibfind:udname];
	ibsta = [gvisa ThreadIbsta];
	iberr = [gvisa ThreadIberr];
	ibcnt =  ibcntl = [gvisa ThreadIbcnt];
	return res;
};
int ibspb( int ud, short *sp_bytes ) {
    ibinit();
	unsigned int res =  [gvisa ibspb:ud:sp_bytes];
	ibsta = [gvisa ThreadIbsta];
	iberr = [gvisa ThreadIberr];
	ibcnt =  ibcntl = [gvisa ThreadIbcnt];
	return res;
};



int ThreadIbsta() { return [gvisa ThreadIbsta]; }
int ThreadIbcnt() { return [gvisa ThreadIbcnt]; }
long ThreadIbcntl() { return [gvisa ThreadIbcnt]; }
int ThreadIberr() { return [gvisa ThreadIberr]; }
