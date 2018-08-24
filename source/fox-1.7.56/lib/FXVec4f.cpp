/********************************************************************************
*                                                                               *
*       S i n g l e - P r e c i s i o n   4 - E l e m e n t   V e c t o r       *
*                                                                               *
*********************************************************************************
* Copyright (C) 1994,2016 by Jeroen van der Zijp.   All Rights Reserved.        *
*********************************************************************************
* This library is free software; you can redistribute it and/or modify          *
* it under the terms of the GNU Lesser General Public License as published by   *
* the Free Software Foundation; either version 3 of the License, or             *
* (at your option) any later version.                                           *
*                                                                               *
* This library is distributed in the hope that it will be useful,               *
* but WITHOUT ANY WARRANTY; without even the implied warranty of                *
* MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the                 *
* GNU Lesser General Public License for more details.                           *
*                                                                               *
* You should have received a copy of the GNU Lesser General Public License      *
* along with this program.  If not, see <http://www.gnu.org/licenses/>          *
********************************************************************************/
#include "xincs.h"
#include "fxver.h"
#include "fxdefs.h"
#include "fxmath.h"
#include "FXArray.h"
#include "FXHash.h"
#include "FXStream.h"
#include "FXObject.h"
#include "FXVec2f.h"
#include "FXVec3f.h"
#include "FXVec4f.h"
#include "FXQuatf.h"


using namespace FX;

/*******************************************************************************/

namespace FX {


// Convert from vector to color
FXColor colorFromVec4f(const FXVec4f& vec){
  return FXRGBA((vec.x*255.0f+0.5f),(vec.y*255.0f+0.5f),(vec.z*255.0f+0.5f),(vec.w*255.0f+0.5f));
  }


// Convert from color to vector
FXVec4f colorToVec4f(FXColor clr){
  return FXVec4f(0.003921568627f*FXREDVAL(clr),0.003921568627f*FXGREENVAL(clr),0.003921568627f*FXBLUEVAL(clr),0.003921568627f*FXALPHAVAL(clr));
  }


// Compute fast dot product with vector code
FXfloat dot(const FXVec4f& u,const FXVec4f& v){
#if defined(FOX_HAS_AVX)
  register __m128 uu=_mm_load_ps(&u[0]);
  register __m128 vv=_mm_load_ps(&v[0]);
  return _mm_cvtss_f32(_mm_dp_ps(uu,vv,0xF1));
#else
  return u*v;
#endif
  }


#if defined(__GNUC__) && defined(__linux__) && defined(__x86_64__)

static inline FXfloat rsqrtf(FXfloat r){
  register FXfloat q=r;
  asm volatile("rsqrtss %0, %0" : "=x" (q) : "0" (q) );
  return (r*q*q-3.0f)*q*-0.5f;
  }

#else

static inline FXfloat rsqrtf(FXfloat r){
  return 1.0f/Math::sqrt(r);
  }

#endif


// Fast normalize vector
FXVec4f fastnormalize(const FXVec4f& v){
  register FXfloat m=dot(v,v);
  FXVec4f result(v);
  if(__likely(FLT_MIN<m)){ result*=rsqrtf(m); }
  return result;
  }


// Normalize vector
FXVec4f normalize(const FXVec4f& v){
  register FXfloat m=dot(v,v);
  FXVec4f result(v);
  if(__likely(0.0f<m)){ result/=Math::sqrt(m); }
  return result;
  }


// Compute plane equation from 3 points a,b,c
FXVec4f plane(const FXVec3f& a,const FXVec3f& b,const FXVec3f& c){
  FXVec3f nm(normal(a,b,c));
  return FXVec4f(nm,-(nm.x*a.x+nm.y*a.y+nm.z*a.z));
  }


// Compute plane equation from vector and distance
FXVec4f plane(const FXVec3f& vec,FXfloat dist){
  FXVec3f nm(normalize(vec));
  return FXVec4f(nm,-dist);
  }


// Compute plane equation from vector and point on plane
FXVec4f plane(const FXVec3f& vec,const FXVec3f& p){
  FXVec3f nm(normalize(vec));
  return FXVec4f(nm,-(nm.x*p.x+nm.y*p.y+nm.z*p.z));
  }


// Compute plane equation from 4 vector
FXVec4f plane(const FXVec4f& vec){
  register FXfloat t=Math::sqrt(vec.x*vec.x+vec.y*vec.y+vec.z*vec.z);
  return FXVec4f(vec.x/t,vec.y/t,vec.z/t,vec.w/t);
  }


// Signed distance normalized plane and point
FXfloat FXVec4f::distance(const FXVec3f& p) const {
  return x*p.x+y*p.y+z*p.z+w;
  }


// Return true if edge a-b crosses plane
FXbool FXVec4f::crosses(const FXVec3f& a,const FXVec3f& b) const {
  return (distance(a)>=0.0f) ^ (distance(b)>=0.0f);
  }


// Linearly interpolate
FXVec4f lerp(const FXVec4f& u,const FXVec4f& v,FXfloat f){
#if defined(FOX_HAS_AVX2) && defined(FOX_HAS_FMA)
  register __m128 u0=_mm_loadu_ps(&u[0]);
  register __m128 v0=_mm_loadu_ps(&v[0]);
  register __m128 ff=_mm_set1_ps(f);
  FXVec4f r;
  _mm_storeu_ps(&r[0],_mm_fmadd_ps(ff,v0,_mm_fnmadd_ps(ff,u0,u0)));       // Lerp in two instructions!
  return r;
#elif defined(FOX_HAS_SSE2)
  register __m128 u0=_mm_loadu_ps(&u[0]);
  register __m128 v0=_mm_loadu_ps(&v[0]);
  register __m128 ff=_mm_set1_ps(f);
  FXVec4f r;
  _mm_storeu_ps(&r[0],_mm_add_ps(u0,_mm_mul_ps(_mm_sub_ps(v0,u0),ff)));
  return r;
#else
  return FXVec4f(u.x+(v.x-u.x)*f,u.y+(v.y-u.y)*f,u.z+(v.z-u.z)*f,u.w+(v.w-u.w)*f);
#endif
  }


// Save vector to stream
FXStream& operator<<(FXStream& store,const FXVec4f& v){
  store << v.x << v.y << v.z << v.w;
  return store;
  }


// Load vector from stream
FXStream& operator>>(FXStream& store,FXVec4f& v){
  store >> v.x >> v.y >> v.z >> v.w;
  return store;
  }

}
