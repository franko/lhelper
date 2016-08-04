/********************************************************************************
*                                                                               *
*                             Regular Expression Test                           *
*                                                                               *
*********************************************************************************
* Copyright (C) 1999,2016 by Jeroen van der Zijp.   All Rights Reserved.        *
********************************************************************************/
#include "fx.h"


/*


*/

#define NCAP 10    // Must be less that or equal to 10


/*******************************************************************************/


// Start the whole thing
int main(int argc,char** argv){
  FXint beg[NCAP]={-1,-1,-1,-1,-1,-1,-1,-1,-1,-1};
  FXint end[NCAP]={-1,-1,-1,-1,-1,-1,-1,-1,-1,-1};
  FXint where;
  FXint ncap=1;
  FXint mode;
  FXRex rex;
  FXRex::Error err;

  fxTraceLevel=101;

  // Got nothing
  if(argc==1){
    fxwarning("no arguments\n");
    exit(1);
    }

  // Just compile pattern arg#1
  if(2<=argc){
    mode=FXRex::Normal;
    mode|=FXRex::Capture;
    mode|=FXRex::NotEmpty;
    mode|=FXRex::Exact;
    err=rex.parse(argv[1],mode);
    fxmessage("parse(\"%s\") = %s\n",argv[1],FXRex::getError(err));
    }

  // Match pattern against arg#2
  if(3<=argc){
    if(4<=argc){
      ncap=strtoul(argv[3],NULL,10);
      if(ncap>NCAP) ncap=NCAP;
      }
    mode=FXRex::Normal;
    //mode|=FXRex::NotBol;
    //mode|=FXRex::NotEol;
    where=rex.search(argv[2],strlen(argv[2]),0,strlen(argv[2]),mode,beg,end,ncap);
    if(0<=where){
      fxmessage("found at %d\n",where);
      for(FXint i=0; i<ncap; i++){
        fxmessage("capture at %d:%d\n",beg[i],end[i]);
        }
      for(FXint i=beg[0]; i<end[0]; i++){
        fxmessage("%c",argv[2][i]);
        }
      fxmessage("\n");
      }
    else{
      fxmessage("no match\n");
      }
    }
  return 1;
  }

