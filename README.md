# Scry
A simple implementation of futures in Zig.  

Comments, suggestions, corrections, etc. are welcome.

### Creating Futures
Futures are created by passing in a type.
```zig
const MyFutureType = scry.Future(i32);
var my_fut = MyFutureType{}; // my_fut is initialized but nothing has happened yet
var buffer_fut = scry.Future([]u8){}; // we don't need to create the type beforehand
```
### Checking Futures
Futures have two flags protected by atomics. However, there is no lock mechanism. Futures work under the assumption of a single producer, single consumer model.
```zig
my_fut.start(..); // 'start' explained below
assert(true == my_fut.started());
while (!my_fut.done()) {} // waiting (probably not doing this in a real setting)
// now our result is ready
```
### Taking Results
There are two methods to get a result and both take ownership. They differ on the semantics required to handle the result.  
`.take()` returns a Result union type (explained below). It allows for switch semantics and coercion.  
```zig
const result = fi32.take();
try testing.expect(.ok == result);
try testing.expect(15 == result.ok);
```
`.takeUnwrapped()` will return the underlying T or error. It allows for normal error handling semantics.  
```zig
const value = try fi32.takeUnwrapped();
try testing.expect(42 == value);
```
Both methods leave the Future with a dummy 'none' result. The future can then be reused with another call to `.start()`.
Taking ownership means that if a producer / promise function allocates memory (by passing in an allocator) then the consumer should free the result.

### Result Union
Results are tagged unions mainly because I just learned about them.  
They take the form of `MyFutureType.Result.ok: T`, `MyFutureType.Result.err: anyerror`, and `MyFutureType.Result.none`.

(Note: `.ok` & `.err` are the interesting union tags, while `.none` is due to my scuffed implementation.)

### Starting Futures
`.start()` needs a pointer to a thread pool, the function to call, and some arguments.
```zig
var futcheck = Future(bool){};
fbuf.start(&pool, doCheck, .{ "GL_ARB_tessellation_shader"});
```
The arguments must be a tuple. The function should return the result or some error.

### Writing Promises
Promise functions are nothing special: return the expected type or an error. A promise for a `Future([]u8)` might look like `loadFile(allocator: Allocator, path: []const u8) ![]u8`.  
