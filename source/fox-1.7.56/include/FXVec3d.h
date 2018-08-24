/********************************************************************************
*                                                                               *
*       D o u b l e - P r e c i s i o n   3 - E l e m e n t   V e c t o r       *
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
#ifndef FXVEC3D_H
#define FXVEC3D_H

namespace FX {


/// Double-precision 3-element vector
class FXAPI FXVec3d {
public:
  FXdouble x;
  FXdouble y;
  FXdouble z;
public:

  /// Default constructor; value is not initialized
  FXVec3d(){}

  /// Initialize from 2-vector
  FXVec3d(const FXVec2d& v,FXdouble s=0.0):x(v.x),y(v.y),z(s){}

  /// Initialize from another vector
  FXVec3d(const FXVec3d& v):x(v.x),y(v.y),z(v.z){}

  /// Initialize from array of doubles
  FXVec3d(const FXdouble v[]):x(v[0]),y(v[1]),z(v[2]){}

  /// Initialize from components
  FXVec3d(FXdouble xx,FXdouble yy,FXdouble zz):x(xx),y(yy),z(zz){}

  /// Return a non-const reference to the ith element
  FXdouble& operator[](FXint i){return (&x)[i];}

  /// Return a const reference to the ith element
  const FXdouble& operator[](FXint i) const {return (&x)[i];}

  /// Assignment
  FXVec3d& operator=(const FXVec3d& v){x=v.x;y=v.y;z=v.z;return *this;}

  /// Assignment from array of doubles
  FXVec3d& operator=(const FXdouble v[]){x=v[0];y=v[1];z=v[2];return *this;}

  /// Set value from another vector
  FXVec3d& set(const FXVec3d& v){x=v.x;y=v.y;z=v.z;return *this;}

  /// Set from array of doubles
  FXVec3d& set(const FXdouble v[]){x=v[0];y=v[1];z=v[2];return *this;}

  /// Set value from components
  FXVec3d& set(FXdouble xx,FXdouble yy,FXdouble zz){x=xx;y=yy;z=zz;return *this;}

  /// Assigning operators
  FXVec3d& operator*=(FXdouble n){ return set(x*n,y*n,z*n); }
  FXVec3d& operator/=(FXdouble n){ return set(x/n,y/n,z/n); }
  FXVec3d& operator+=(const FXVec3d& v){ return set(x+v.x,y+v.y,z+v.z); }
  FXVec3d& operator-=(const FXVec3d& v){ return set(x-v.x,y-v.y,z-v.z); }
  FXVec3d& operator^=(const FXVec3d& v){ return set(y*v.z-z*v.y,z*v.x-x*v.z,x*v.y-y*v.x); }

  /// Conversions
  operator FXdouble*(){return &x;}
  operator const FXdouble*() const {return &x;}
  operator FXVec2d&(){return *reinterpret_cast<FXVec2d*>(this);}
  operator const FXVec2d&() const {return *reinterpret_cast<const FXVec2d*>(this);}

  /// Test if zero
  FXbool operator!() const { return x==0.0 && y==0.0 && z==0.0; }

  /// Unary
  FXVec3d operator+() const { return *this; }
  FXVec3d operator-() const { return FXVec3d(-x,-y,-z); }

  /// Length and square of length
  FXdouble length2() const { return x*x+y*y+z*z; }
  FXdouble length() const { return Math::sqrt(length2()); }

  /// Clamp values of vector between limits
  FXVec3d& clamp(FXdouble lo,FXdouble hi){ return set(Math::fclamp(lo,x,hi),Math::fclamp(lo,y,hi),Math::fclamp(lo,z,hi)); }

  /// Destructor
 ~FXVec3d(){}
  };


/// Dot product
inline FXdouble operator*(const FXVec3d& a,const FXVec3d& b){ return a.x*b.x+a.y*b.y+a.z*b.z; }

/// Cross product
inline FXVec3d operator^(const FXVec3d& a,const FXVec3d& b){ return FXVec3d(a.y*b.z-a.z*b.y, a.z*b.x-a.x*b.z, a.x*b.y-a.y*b.x); }

/// Scaling
inline FXVec3d operator*(const FXVec3d& a,FXdouble n){return FXVec3d(a.x*n,a.y*n,a.z*n);}
inline FXVec3d operator*(FXdouble n,const FXVec3d& a){return FXVec3d(n*a.x,n*a.y,n*a.z);}
inline FXVec3d operator/(const FXVec3d& a,FXdouble n){return FXVec3d(a.x/n,a.y/n,a.z/n);}
inline FXVec3d operator/(FXdouble n,const FXVec3d& a){return FXVec3d(n/a.x,n/a.y,n/a.z);}

/// Vector and vector addition
inline FXVec3d operator+(const FXVec3d& a,const FXVec3d& b){ return FXVec3d(a.x+b.x,a.y+b.y,a.z+b.z); }
inline FXVec3d operator-(const FXVec3d& a,const FXVec3d& b){ return FXVec3d(a.x-b.x,a.y-b.y,a.z-b.z); }

/// Equality tests
inline FXbool operator==(const FXVec3d& a,FXdouble n){return a.x==n && a.y==n && a.z==n;}
inline FXbool operator!=(const FXVec3d& a,FXdouble n){return a.x!=n || a.y!=n || a.z!=n;}
inline FXbool operator==(FXdouble n,const FXVec3d& a){return n==a.x && n==a.y && n==a.z;}
inline FXbool operator!=(FXdouble n,const FXVec3d& a){return n!=a.x || n!=a.y || n!=a.z;}

/// Equality tests
inline FXbool operator==(const FXVec3d& a,const FXVec3d& b){ return a.x==b.x && a.y==b.y && a.z==b.z; }
inline FXbool operator!=(const FXVec3d& a,const FXVec3d& b){ return a.x!=b.x || a.y!=b.y || a.z!=b.z; }

/// Inequality tests
inline FXbool operator<(const FXVec3d& a,FXdouble n){return a.x<n && a.y<n && a.z<n;}
inline FXbool operator<=(const FXVec3d& a,FXdouble n){return a.x<=n && a.y<=n && a.z<=n;}
inline FXbool operator>(const FXVec3d& a,FXdouble n){return a.x>n && a.y>n && a.z>n;}
inline FXbool operator>=(const FXVec3d& a,FXdouble n){return a.x>=n && a.y>=n && a.z>=n;}

/// Inequality tests
inline FXbool operator<(FXdouble n,const FXVec3d& a){return n<a.x && n<a.y && n<a.z;}
inline FXbool operator<=(FXdouble n,const FXVec3d& a){return n<=a.x && n<=a.y && n<=a.z;}
inline FXbool operator>(FXdouble n,const FXVec3d& a){return n>a.x && n>a.y && n>a.z;}
inline FXbool operator>=(FXdouble n,const FXVec3d& a){return n>=a.x && n>=a.y && n>=a.z;}

/// Inequality tests
inline FXbool operator<(const FXVec3d& a,const FXVec3d& b){ return a.x<b.x && a.y<b.y && a.z<b.z; }
inline FXbool operator<=(const FXVec3d& a,const FXVec3d& b){ return a.x<=b.x && a.y<=b.y && a.z<=b.z; }
inline FXbool operator>(const FXVec3d& a,const FXVec3d& b){ return a.x>b.x && a.y>b.y && a.z>b.z; }
inline FXbool operator>=(const FXVec3d& a,const FXVec3d& b){ return a.x>=b.x && a.y>=b.y && a.z>=b.z; }

/// Lowest or highest components
inline FXVec3d lo(const FXVec3d& a,const FXVec3d& b){return FXVec3d(Math::fmin(a.x,b.x),Math::fmin(a.y,b.y),Math::fmin(a.z,b.z));}
inline FXVec3d hi(const FXVec3d& a,const FXVec3d& b){return FXVec3d(Math::fmax(a.x,b.x),Math::fmax(a.y,b.y),Math::fmax(a.z,b.z));}

/// Convert vector to color
extern FXAPI FXColor colorFromVec3d(const FXVec3d& vec);

/// Convert color to vector
extern FXAPI FXVec3d colorToVec3d(FXColor clr);

/// Compute normal from three points a,b,c
extern FXAPI FXVec3d normal(const FXVec3d& a,const FXVec3d& b,const FXVec3d& c);

/// Compute approximate normal from four points a,b,c,d
extern FXAPI FXVec3d normal(const FXVec3d& a,const FXVec3d& b,const FXVec3d& c,const FXVec3d& d);

/// Normalize vector
extern FXAPI FXVec3d normalize(const FXVec3d& v);

/// Linearly interpolate
extern FXAPI FXVec3d lerp(const FXVec3d& u,const FXVec3d& v,FXdouble f);

/// Save vector to a stream
extern FXAPI FXStream& operator<<(FXStream& store,const FXVec3d& v);

/// Load vector from a stream
extern FXAPI FXStream& operator>>(FXStream& store,FXVec3d& v);

}

#endif
