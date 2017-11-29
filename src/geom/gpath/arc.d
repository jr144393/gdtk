// arc.d
// Peter J. 2017-11-29: Split out of the original path module.

module geom.gpath.arc;

import std.conv;
import std.math;

import nm.bbla;
import geom.elements;
import geom.gpath.path;


class Arc : Path {
public:
    Vector3 a; // beginning point (t = 0)
    Vector3 b; // end point (t = 1)
    Vector3 c; // centre of curvature
    // Arc constructed from start-point a, end-point b and centre of curvature c.
    this(in Vector3 a, in Vector3 b, in Vector3 c)
    {
	this.a = a; this.b = b; this.c = c;
    }
    this(ref const(Arc) other)
    {
	a = other.a; b = other.b; c = other.c;
    }
    override Arc dup() const
    {
	return new Arc(a, b, c);
    }
    override Vector3 opCall(double t) const 
    {
	double L;
	Vector3 p;
	evaluate_position_and_length(t, p, L);
	return p;
    }
    override string toString() const
    {
	return "Arc(a=" ~ to!string(a) ~ ", b=" ~ to!string(b) ~ ", c=" ~ to!string(c) ~ ")";
    }
    override string classString() const
    {
	return "Arc";
    }
    override double length() const
    {
	// Returns the geometric length.
	double L;
	Vector3 p;
	evaluate_position_and_length(1.0, p, L);
	return L;
    }
    
    void evaluate_position_and_length(in double t, out Vector3 loc, out double L) const
    {
	// Both the position of the point and the length of the full arc are evaluated
	// using mostly the same process of transforming to the plane local to the arc.
	Vector3 ca, cb, tangent1, tangent2, n, cb_local;
	double ca_mag, cb_mag, theta;

	L = 0.0;
	ca = a - c; ca_mag = abs(ca);
	cb = b - c; cb_mag = abs(cb);
	if ( fabs(ca_mag - cb_mag) > 1.0e-5 ) {
	    throw new Error(text("Arc.evaluate(): radii do not match ca=",ca," cb=",cb));
	}
	// First vector in plane.
	tangent1 = Vector3(ca); tangent1.normalize(); 
	// Compute unit normal to plane of all three points.
	n = cross(ca, cb);
	if ( abs(n) > 0.0 ) {
	    n.normalize();
	} else {
	    throw new Error(text("Arc.evaluate(): cannot find plane of three points."));
	}
	// Third (orthogonal) vector is in the original plane.
	tangent2 = cross(n, tangent1); 
	// Now transform to local coordinates so that we can do 
	// the calculation of the point along the arc in 
	// the local xy-plane, with ca along the x-axis.
	cb_local = cb;
	Vector3 zero = Vector3(0.0,0.0,0.0);
	cb_local.transform_to_local_frame(tangent1, tangent2, n, zero);
	if ( fabs(cb_local.z) > 1.0e-6 ) {
	    throw new Error(text("Arc.evaluate(): problem with transformation cb_local=", cb_local));
	}
	// Angle of the final point on the arc is in the range -pi < th <= +pi.
	theta = atan2(cb_local.y, cb_local.x);
	// The length of the circular arc.
	L = theta * cb_mag;
	// Move the second point around the arc in the local xy-plane.
	theta *= t;
	loc.set(cos(theta)*cb_mag, sin(theta)*cb_mag, 0.0);
	// Transform back to global xyz coordinates
	// and remember to add the centre coordinates.
	loc.transform_to_global_frame(tangent1, tangent2, n, c);
    } // end evaluate_position_and_length()
} // end class Arc

class Arc3 : Arc {
    // Arc constructed from start-point a, end-point b and another intermediate point m.
    // Internally it is stored as an Arc object.
    Vector3 m;
    this(in Vector3 a, in Vector3 m, in Vector3 b)
    {
	Vector3 n = cross(m - a, m - b); // normal to plane of arc
	if (abs(n) <= 1.0e-11) {
	    throw new Error(text("Arc3: Points appear colinear.",
				 " a=", to!string(a),
				 " m=", to!string(m),
				 " b=", to!string(b)));
	}
	// The centre of the circle lies along the bisector of am and 
	// the bisector of mb.
	Vector3 mid_am = 0.5 * (a + m);
	Vector3 bisect_am = cross(n, a - m);
	Vector3 mid_mb = 0.5 * (b + m);
	Vector3 bisect_mb = cross(n, b - m);
	// Solve least-squares problem to get s_am, s_mb.
	auto amatrix = new Matrix([[bisect_am.x, bisect_mb.x],
				   [bisect_am.y, bisect_mb.y],
				   [bisect_am.z, bisect_mb.z]]);
	Vector3 diff_mid = mid_mb - mid_am;
	auto rhs = new Matrix([diff_mid.x, diff_mid.y, diff_mid.z], "column");
	auto s_values = lsqsolve(amatrix, rhs);
	double s_am = s_values[0,0];
	double s_mb = s_values[1,0];
	Vector3 c = mid_am + s_am * bisect_am;
	Vector3 c_check = mid_mb + s_mb * bisect_mb;
	Vector3 delc = c_check - this.c;
	if (abs(delc) > 1.0e-9) {
	    throw new Error(text("Arc3: Points inconsistent centre estimates.",
				 " c=", to!string(this.c),
				 " c_check=", to!string(c_check)));
	}
	super(a, b, c);
	this.m = m;
    }
    this(ref const(Arc3) other)
    {
	this(other.a, other.m, other.b);
    }
    override Arc3 dup() const
    {
	return new Arc3(a, m, b);
    }
    override string toString() const
    {
	return "Arc3(a=" ~ to!string(a) ~ ", m=" ~ to!string(m) ~ ", b=" ~ to!string(b) ~ ")";
    }
    override string classString() const
    {
	return "Arc3";
    }
} // end class Arc3

unittest {
    auto a = Vector3([2.0, 2.0, 0.0]);
    auto b = Vector3([1.0, 2.0, 1.0]);
    auto c = Vector3([1.0, 2.0, 0.0]);
    auto abc = new Arc(a, b, c);
    auto d = abc(0.5);
    assert(approxEqualVectors(d, Vector3(1.7071068, 2.0, 0.7071068)), "Arc");
    auto adb = new Arc3(a, d, b);
    assert(approxEqualVectors(d, adb(0.5)), "Arc3");
    //
    auto pth = new Arc3(Vector3(0.0,1.0), Vector3(0.5,1.2), Vector3(1.0,1.0));
    auto ps = Vector3(0.5,0.5);
    auto dir = Vector3(0.0,1.0);
    double t;
    auto found = pth.intersect2D(ps, dir, t, 10);
    assert(found, "intersect2D not found on Arc3");
    assert(approxEqual(t,0.5), "intersect2D parametric location on Arc3");
}

