# Scry
A simple implementation of futures in Zig.  

Comments, suggestions, corrections, etc. are welcome.

### Creating Futures
Futures are created by passing in a type.
```zig
const MyFutureType = scry.Future(i32);
var my_fut = MyFutureType{}; // my_fut is initialized but nothing has happened yet
var other_fut = scry.Future(f64){}; // we don't need to create the type beforehand
```

### Checking Futures
Futures have two flags protected by atomics. However, there is no lock mechanism. Futures work under the assumption of a single producer, single consumer model.
```zig
my_fut.start(..); // 'start' explained below
assert(true == my_fut.started());
while (!my_fut.done()) {} // waiting (probably not doing this in a real setting)
// now our result is ready
```

### Memory Hygiene
Producers allocate the result and consumers free the result. Futures don't have a deinit-like method (yet?) so it's important to inspect the result and, if there's no error, free the slice.

### Taking Results
There are two methods to get a result and both take ownership. They differ on the semantics required to handle the result.  
`.take()` returns a Result union type (explained below). It allows for switch semantics and coercion.  
```zig
const result = fi32.take();
try testing.expect(.ok == result);
try testing.expect(1 == result.ok.len);
try testing.expect(15 == result.ok[0]);
allocator.free(result.ok);
```
`.takeUnwrapped()` takes the Result and, if ok, returns the []T slice or, if not ok, it errors. It allows for normal error handling semantics.  
```zig
const value = try fi32.takeUnwrapped();
try testing.expect(1 == value.len);
try testing.expect(42 == value[0]);
allocator.free(value);
```
Both methods leave the Future with a dummy 'none' result. The future can then be reused with another call to `.start()`.

### Result Union
Results are tagged unions mainly because I just learned about them.  
They take the form of `MyFutureType.Result.ok: []T`, `MyFutureType.Result.err: anyerror`, and `MyFutureType.Result.none`.

(Note: `.ok` & `.err` are the interesting union tags, while `.none` is due to my scuffed implementation.)

### Starting Futures
`.start()` needs a pointer to a thread pool, the function to call, and some arguments.
```zig
var fbuf = Future(u8){};
fbuf.start(&pool, loadFile, .{ allocator, "data/config.lua" });
```
Arguments to the promise function need to be a tuple. There's no requirements for specific arguments; Futures just want a slice (or error) from the promise function.

### Writing Promises
Promise functions are nothing special: return either a slice or an error. The type of slice they return must match the type of Future.  
If promises are to access shared resources then those resources need their own locks, etc.
