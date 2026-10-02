/* More embedding checks for example.c (user classes with C opaque data,
   finalizers, class-id checks, C-created closures, C -> JS callbacks). */
function check(cond, msg) {
    if (!cond)
        throw Error("test_rect_more: " + msg);
}
function throws(f, msg) {
    var threw = false;
    try { f(); } catch (e) { threw = true; }
    check(threw, msg + " should throw");
}

/* instanceof / prototype chain across the two C classes */
var r = new Rectangle(1, 2), fr = new FilledRectangle(3, 4, 5);
check(r instanceof Rectangle, "r instanceof Rectangle");
check(fr instanceof FilledRectangle && fr instanceof Rectangle, "fr inherits Rectangle");
check(!(r instanceof FilledRectangle), "r is not a FilledRectangle");

/* C getters check the class id: reaching them through an object that only
   inherits the prototype is a TypeError, not a crash */
var fake = Object.create(Rectangle.prototype);
var fake2 = Object.create(FilledRectangle.prototype);
throws(function () { return fake.x; }, "x getter on plain object");
throws(function () { return fake2.color; }, "color getter on plain object");
check(fr.x === 3 && fr.y === 4 && fr.color === 5, "getters on subclass instance");

/* exceptions thrown by a JS callback propagate through the C caller */
throws(function () { Rectangle.call(function () { throw Error("boom"); }, 1); }, "callback throw");
check(Rectangle.call(function (p) { return p * 2; }, 21) === 42, "callback number");
check(Rectangle.call(function (p) { return [p]; }, 7)[0] === 7, "callback object");

/* churn: many C-backed objects and C-created closures must survive and be
   reclaimed across GCs (finalizers run; valgrind checks the C side) */
var keep = [], i, f;
for (i = 0; i < 20000; i++) {
    r = (i & 1) ? new FilledRectangle(i, -i, i & 0xff) : new Rectangle(i, -i);
    if ((i % 1000) == 0)
        keep.push(r);
    f = Rectangle.getClosure("c" + i);
    if ((i % 997) == 0)
        keep.push(f);
}
for (i = 0; i < keep.length; i++) {
    if (typeof keep[i] === "function")
        check(keep[i]().charAt(0) === "c", "closure survived GC");
    else
        check(keep[i].y === -keep[i].x, "object survived GC");
}
