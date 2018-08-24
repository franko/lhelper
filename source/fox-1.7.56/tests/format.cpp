/********************************************************************************
*                                                                               *
*                             String Format I/O Test                            *
*                                                                               *
*********************************************************************************
* Copyright (C) 2007,2016 by Jeroen van der Zijp.   All Rights Reserved.        *
********************************************************************************/
#include "fx.h"
//#include <locale.h>


/*
  Notes:
  - Test battery for fxprintf().
*/


/*******************************************************************************/

namespace FX {

extern FXint __snprintf(FXchar* string,FXint length,const FXchar* format,...);
extern FXint __sscanf(const FXchar* string,const FXchar* format,...);

}

const FXchar *floatformat[]={
  "%.10e",
  "%'.5e",
  "%10.5f",
  "%-10.5f",
  "%+10.5f",
  "% 10.5f",
  "%123.9f",
  "%+22.9f",
  "%+4.9f",
  "%01.3f",
  "%4f",
  "%3.1f",
  "%3.2f",
  "%.0f",
  "%.3f",
  "%'.8f",
  "%+.3g",
  "%#.3g",
  "%.g",
  "%#.g",
  "%g",
  "%#g",
  "%'.8g"
  };


const double floatnumbers[]={
  0.000000001,
  -1.5,
  0.8,
  1.0,
  10.0,
  100.0,
  1000.0,
  10000.0,
  999.0,
  1010.0,
  134.21,
  91340.2,
  341.1234,
  0203.9,
  0.96,
  0.996,
  0.9996,
  1.996,
  4.136,
  6442452944.1234,
  1.23456789E+20,
  0.123456789,
  2.2250738585072014e-308,
  1.7976931348623157e+308,
  0.0,
  -0.0
  };


// Use a trick to get a nan
#if FOX_BIGENDIAN
const FXuint doublenan[2]={0x7fffffff,0xffffffff};
const FXuint doubleinf[2]={0x7ff00000,0x00000000};
#else
const FXuint doublenan[2]={0xffffffff,0x7fffffff};
const FXuint doubleinf[2]={0x00000000,0x7ff00000};
#endif


const FXchar *intformat[]={
  "%d",
  "%'d",
  "%02x",
  "%0.2x",
  "%-8d",
  "%8d",
  "%08d",
  "%.6d",
  "%u",
  "%+i",
  "% i",
  "%x",
  "%#x",
  "%#08x",
  "%o",
  "%#o",
  "%.32b"
  };

const FXint intnumbers[]={
  0,
  1,
  -1,
  0x90,
  -34,
  2147483647,
  -2147483648
  };


const FXchar *positionalformat[]={
  "%d%d%d",
  "%3$d%2$d%1$d",
  "%2$*1$d%3$d"
  };

const FXchar *positionalformat2="%1$*2$.*3$lf";

const FXchar *positionalformat3="%3$d%3$d";


// Uncomment to revert to native version
//#define __snprintf snprintf


// Start
int main(int,char*[]){
  FXchar buffer[1024];
  FXuint x,y;

  //setlocale(LC_ALL,"");

  // Testing int formats
  for(x=0; x<ARRAYNUMBER(intformat); x++){
    for(y=0; y<ARRAYNUMBER(intnumbers); y++){
      __snprintf(buffer,sizeof(buffer),intformat[x],intnumbers[y]);
      fprintf(stdout,"format=\"%s\" output=\"%s\"\n",intformat[x],buffer);
      }
    }

  fprintf(stdout,"\n");

  // Testing double formats
  for(x=0; x<ARRAYNUMBER(floatformat); x++){
    for(y=0; y<ARRAYNUMBER(floatnumbers); y++){
      __snprintf(buffer,sizeof(buffer),floatformat[x],floatnumbers[y]);
      fprintf(stdout,"format=\"%s\" output=\"%s\"\n",floatformat[x],buffer);
      }
    }

  fprintf(stdout,"\n");

  // Testing Inf's
  for(x=0; x<ARRAYNUMBER(floatformat); x++){
    __snprintf(buffer,sizeof(buffer),floatformat[x],*((const FXdouble*)&doubleinf));
    fprintf(stdout,"format=\"%s\" output=\"%s\"\n",floatformat[x],buffer);
    }

  fprintf(stdout,"\n");

  // Testing NaN's
  for(x=0; x<ARRAYNUMBER(floatformat); x++){
    __snprintf(buffer,sizeof(buffer),floatformat[x],*((const FXdouble*)&doublenan));
    fprintf(stdout,"format=\"%s\" output=\"%s\"\n",floatformat[x],buffer);
    }

  fprintf(stdout,"\n");

  // Testing positional formats
  for(x=0; x<ARRAYNUMBER(positionalformat); x++){
    __snprintf(buffer,sizeof(buffer),positionalformat[x],10,20,30);
    fprintf(stdout,"format=\"%s\" output=\"%s\"\n",positionalformat[x],buffer);
    }

  fprintf(stdout,"\n");

  __snprintf(buffer,sizeof(buffer),positionalformat2,3.14159265358979,20,10);
  fprintf(stdout,"format=\"%s\" output=\"%s\"\n",positionalformat2,buffer);

  __snprintf(buffer,sizeof(buffer),positionalformat3,10,20,30);
  fprintf(stdout,"format=\"%s\" output=\"%s\"\n",positionalformat3,buffer);

  int num=0;
  __sscanf("199,999","%'d",&num);
  fprintf(stdout,"num=%d\n",num);

  __sscanf("1,999,9","%'d",&num);
  fprintf(stdout,"num=%d\n",num);

  __sscanf("1,999,99","%'d",&num);
  fprintf(stdout,"num=%d\n",num);

  __sscanf("1,999,999","%'d",&num);
  fprintf(stdout,"num=%d\n",num);

  __sscanf("1999,999","%'d",&num);
  fprintf(stdout,"num=%d\n",num);

  return 0;
  }

