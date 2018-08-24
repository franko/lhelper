/********************************************************************************
*                                                                               *
*                             String Format I/O Test                            *
*                                                                               *
*********************************************************************************
* Copyright (C) 2007,2016 by Jeroen van der Zijp.   All Rights Reserved.        *
********************************************************************************/
#include "fx.h"

/*
  Notes:
  - Test battery for fxscanf().
*/


/*******************************************************************************/

namespace FX {

extern FXint __sscanf(const FXchar* string,const FXchar* format,...);

}

const FXchar *intformat[]={
  "%d %d %d",
  "%i %i %i",
  "%u %u %u",
  "%x %x %x",
  "%o %o %o",
  "%b %b %b",
  "%1d %1d %1d",
  "%0d %0d %0d",
  "%3d %3d %3d",
  "%3$i %1$i %2$i"
  };


const FXchar *intnumbers[]={
  "111 222 333",
  "-111 +222 -333",
  "0xff 0377 123456789",
  "11111111 10101010 0b1111111111111111111111111111111",
  "4294967295 2147483647 -2147483648"
  };


const FXchar* floatformat[]={
  "%lf %lf %lf",
  "%3$lf %1$lf %2$lf"
  };


const FXchar *floatnumbers[]={
  "0.0 1.0 3.1415926535897932384626433833",
  "-0.1 +0.11111 -1.23456789E-99",
  "1.7976931348623157e+308 2.2250738585072014e-308 1.17549435e-38",
  "1.8e+308 4.94065645841246544177e-324 0.0E400"
  };


const FXchar *stringformat[]={
  "%s",
  "%4s",
  "%[0-9.Ee+-]",
  "%[^a-c]",
  "%[]]",
  "%[0-9-]",
  "%[a-a]",
  "%[a-zA-Z0-9_]"
  };

const FXchar *stringinputs[]={
  "1.0E-99",
  "123abc",
  "]]]][[[[",
  "123-1456",
  "aaaaabbbb",
  "Camel_Case_1337"
  };


// Uncomment to revert to native version
//#define __sscanf sscanf


// Start
int main(int,char*[]){
  FXuint   x,y;
  FXint    res;
  FXint    ia,ib,ic;
  FXdouble da,db,dc;
  FXchar   buf[1000];

  // Reading integers
  for(x=0; x<ARRAYNUMBER(intformat); x++){
    for(y=0; y<ARRAYNUMBER(intnumbers); y++){
      ia=ib=ic=0;
      res=__sscanf(intnumbers[y],intformat[x],&ia,&ib,&ic);
      fprintf(stdout,"format=\"%s\" input=\"%s\" res=%d a=%d b=%d c=%d\n",intformat[x],intnumbers[y],res,ia,ib,ic);
      }
    }

  // Reading floats
  for(x=0; x<ARRAYNUMBER(floatformat); x++){
    for(y=0; y<ARRAYNUMBER(floatnumbers); y++){
      da=db=dc=0;
      res=__sscanf(floatnumbers[y],floatformat[x],&da,&db,&dc);
      fprintf(stdout,"format=\"%s\" input=\"%s\" res=%d a=%.16g b=%.16g c=%.16g\n",floatformat[x],floatnumbers[y],res,da,db,dc);
      }
    }

  // Reading strings
  for(x=0; x<ARRAYNUMBER(stringformat); x++){
    for(y=0; y<ARRAYNUMBER(stringinputs); y++){
      res=__sscanf(stringinputs[y],stringformat[x],buf);
      fprintf(stdout,"format=\"%s\" input=\"%s\" res=%d str=%s\n",stringformat[x],stringinputs[y],res,buf);
      }
    }

  return 1;
  }

