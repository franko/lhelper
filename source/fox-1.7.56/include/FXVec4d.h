/********************************************************************************
*                                                                               *
*       D o u b l e - P r e c i s i o n   4 - E l e m e n t   V e c t o r       *
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
#ifndef FXVEC4D_H
#define FXVEC4D_H

namespace FX {


/// Double-precision 4-element vector
class FXAPI FXVec4d {
public:
  FXdouble x;
  FXdouble y;
  FXdouble z;
  FXdouble w;
public:

  /// Default constructor; value is not initialized
  FXVec4d(){}

  /// Construct with 3-vector
  FXVec4d(const FXVec3d& v,FXdouble s=0.0):x(v.x),y(v.y),z(v.z),w(s){}

  /// Initialize from another vector
  FXVec4d(const FXVec4d& v):x(v.x),y(v.y),z(v.z),w(v.w){}

  /// Initialize from array of doubles
  FXVec4d(const FXdouble v[]):x(v[0]),y(v[1]),z(v[2]),w(v[3]){}

  /// Initialize with components
  FXVec4d(FXdouble xx,FXdouble yy,FXdouble zz,FXdouble ww):x(xx),y(yy),z(zz),w(ww){}

  /// Return a non-const reference to the ith element
  FXdouble& operator[](FXint i){return (&x)[i];}

  /// Return a const reference to the ith element
  const FXdouble& operator[](FXint i) const {return (&x)[i];}

  /// Assignment
  FXVec4d& operator=(const FXVec4d& v){x=v.x;y=v.y;z=v.z;w=v.w;return *this;}

  /// Assignment from array of doubles
  FXVec4d& operator=(const FXdouble v[]){x=v[0];y=v[1];z=v[2];w=v[3];return *this;}

  /// Set value from another vector
  FXVec4d& set(const FXVec4d& v){x=v.x;y=v.y;z=v.z;w=v.w;return *this;}

  /// Set value from array of doubles
  FXVec4d& set(const FXdouble v[]){x=v[0];y=v[1];z=v[2];w=v[3];return *this;}

  /// Set value from components
  FXVec4d& set(FXdouble xx,FXdouble yy,FXdouble zz,FXdouble ww){x=xx;y=yy;z=zz;w=ww;return *this;}

  /// Assigning operators
  FXVec4d& operator*=(FXdouble n){ return set(x*n,y*n,z*n,w*n); }
  FXVec4d& operator/=(FXdouble n){ return set(x/n,y/n,z/n,w/n); }
  FXVec4d& operator+=(const FXVec4d& v){ return set(x+v.x,y+v.y,z+v.z,w+v.w); }
  FXVec4d& operator-=(const FXVec4d& v){ return set(x-v.x,y-v.y,z-v.z,w-v.w); }

  /// Conversion
  operator FXdouble*(){return &x;}
  operator const FXdouble*() const {return &x;}
  operator FXVec3d&(){return *reinterpret_cast<FXVec3d*>(this);}
  operator const FXVec3d&() const {return *reinterpret_cast<const FXVec3d*>(this);}

  /// Test if zero
  FXbool operator!() const {return x==0.0 && y==0.0 && z==0.0 && w==0.0; }

  /// Unary
  FXVec4d operator+() const { return *this; }
  FXVec4d operator-() const { return FXVec4d(-x,-y,-z,-w); }

  /// Length and square of length
  FXdouble length2() const { return x*x+y*y+z*z+w*w; }
  FXdouble length() const { return Math::sqrt(length2()); }

  /// Clamp values of vector between limits
  FXVec4d& clamp(FXdouble lo,FXdouble hi){ return set(Math::fclamp(lo,x,hi),Math::fclamp(lo,y,hi),Math::fclamp(lo,z,hi),Math::fclamp(lo,w,hi)); }

  /// Signed distance normalized plane and point
  FXdouble distance(const FXVec3d& p) const;

  /// Return true if edge a-b crosses plane
  FXbool crosses(const FXVec3d& a,const FXVec3d& b) const;

  /// Destructor
 ~FXVec4d(){}
  };


/// Dot product
inline FXdouble operator*(const FXVec4d& a,const FXVec4d& b){ return a.x*b.x+a.y*b.y+a.z*b.z+a.w*b.w; }

/// Scaling
inline FXVec4d operator*(const FXVec4d& a,FXdouble n){return FXVec4d(a.x*n,a.y*n,a.z*n,a.w*n);}
inline FXVec4d operator*(FXdouble n,const FXVec4d& a){return FXVec4d(n*a.x,n*a.y,n*a.z,n*a.w);}
inline FXVec4d operator/(const FXVec4d& a,FXdouble n){return FXVec4d(a.x/n,a.y/n,a.z/n,a.w/n);}
inline FXVec4d operator/(FXdouble n,const FXVec4d& a){return FXVec4d(n/a.x,n/a.y,n/a.z,n/a.w);}

/// Vector and vector addition
inline FXVec4d operator+(const FXVec4d& a,const FXVec4d& b){ return FXVec4d(a.x+b.x,a.y+b.y,a.z+b.z,a.w+b.w); }
inline FXVec4d operator-(const FXVec4d& a,const FXVec4d& b){ return FXVec4d(a.x-b.x,a.y-b.y,a.z-b.z,a.w-b.w); }

/// Equality tests
inline FXbool operator==(const FXVec4d& a,FXdouble n){return a.x==n && a.y==n && a.z==n && a.w==n;}
inline FXbool operator!=(const FXVec4d& a,FXdouble n){return a.x!=n || a.y!=n || a.z!=n || a.w!=n;}
inline FXbool operator==(FXdouble n,const FXVec4d& a){return n==a.x && n==a.y && n==a.z && n==a.w;}
inline FXbool operator!=(FXdouble n,const FXVec4d& a){return n!=a.x || n!=a.y || n!=a.z || n!=a.w;}

/// Equality tests
inline FXbool operator==(const FXVec4d& a,const FXVec4d& b){ return a.x==b.x && a.y==b.y && a.z==b.z && a.w==b.w; }
inline FXbool operator!=(const FXVec4d& a,const FXVec4d& b){ return a.x!=b.x || a.y!=b.y || a.z!=b.z || a.w!=b.w; }

/// Inequality tests
inline FXbool operator<(const FXVec4d& a,FXdouble n){return a.x<n && a.y<n && a.z<n && a.w<n;}
inline FXbool operator<=(const FXVec4d& a,FXdouble n){return a.x<=n && a.y<=n && a.z<=n && a.w<=n;}
inline FXbool operator>(const FXVec4d& a,FXdouble n){return a.x>n && a.y>n && a.z>n && a.w>n;}
inline FXbool operator>=(const FXVec4d& a,FXdouble n){return a.x>=n && a.y>=n && a.z>=n && a.w>=n;}

/// Inequality tests
inline FXbool operator<(FXdouble n,const FXVec4d& a){return n<a.x && n<a.y && n<a.z && n<a.w;}
inline FXbool operator<=(FXdouble n,const FXVec4d& a){return n<=a.x && n<=a.y && n<=a.z && n<=a.w;}
inline FXbool operator>(FXdouble n,const FXVec4d& a){return n>a.x && n>a.y && n>a.z && n>a.w;}
inline FXbool operator>=(FXdouble n,const FXVec4d& a){return n>=a.x && n>=a.y && n>=a.z && n>=a.w;}

/// Inequality tests
inline FXbool operator<(const FXVec4d& a,const FXVec4d& b){ return a.x<b.x && a.y<b.y && a.z<b.z && a.w<b.w; }
inline FXbool operator<=(const FXVec4d& a,const FXVec4d& b){ return a.x<=b.x && a.y<=b.y && a.z<=b.z && a.w<=b.w; }
inline FXbool operator>(const FXVec4d& a,const FXVec4d& b){ return a.x>b.x && a.y>b.y && a.z>b.z && a.w>b.w; }
inline FXbool operator>=(const FXVec4d& a,const FXVec4d& b){ return a.x>=b.x && a.y>=b.y && a.z>=b.z && a.w>=b.w; }

/// Lowest or highest components
inline FXVec4d lo(const FXVec4d& a,const FXVec4d& b){return FXVec4d(Math::fmin(a.x,b.x),Math::fmin(a.y,b.y),Math::fmin(a.z,b.z),Math::fmin(a.w,b.w));}
inline FXVec4d hi(const FXVec4d& a,const FXVec4d& b){return FXVec4d(Math::fmax(a.x,b.x),Math::fmax(a.y,b.y),Math::fmax(a.z,b.z),Math::fmax(a.w,b.w));}

/// Compute normalized plane equation ax+by+cz+d=0
extern FXAPI FXVec4d plane(const FXVec4d& vec);
extern FXAPI FXVec4d plane(const FXVec3d& vec,FXdouble dist);
extern FXAPI FXVec4d plane(const FXVec3d& vec,const FXVec3d& p);
extern FXAPI FXVec4d plane(const FXVec3d& a,const FXVec3d& b,const FXVec3d& c);

/// Convert vector to color
extern FXAPI FXColor colorFromVec4d(const FXVec4d& vec);

/// Convert color to vector
extern FXAPI FXVec4d colorToVec4d(FXColor clr);

/// Normalize vector
extern FXAPI FXVec4d normalize(const FXVec4d& v);

/// Linearly interpolate
extern FXAPI FXVec4d lerp(const FXVec4d& u,const FXVec4d& v,FXdouble f);

/// Save vector to a stream
extern FXAPI FXStream& operator<<(FXStream& store,const FXVec4d& v);

/// Load vector from a stream
extern FXAPI FXStream& operator>>(FXStream& store,FXVec4d& v);

}

#endif
