## Scry
A simple implementation of futures in Zig.  

Comments, suggestions, corrections, etc. are welcome.

#### Creating Futures
Futures are created by passing in a type.
```zig
const MyFutureType = scry.Future(i32);
var my_fut = MyFutureType{}; // my_fut is initialized but nothing has happened yet
var other_fut = scry.Future(f64){}; // we don't need to create the type beforehand
```

#### Checking Futures
Futures have two flags protected by atomics. However, there is no lock mechanism. Futures work under the
assumption of a single producer, single consumer model.
```zig
my_fut.start(..); // 'start' explained below
assert(true == my_fut.started());
while (!my_fut.done()) {} // waiting (probably not doing this in a real setting)
// now our result is ready
```

#### Memory Hygiene
Producers allocate the result and consumers free the result. Futures don't have a deinit-like method (yet?) so it's
important to inspect the result and, if there's no error, free the slice.

#### Taking Results
There are two methods to get a result and both take ownership. They differ on the semantics required to handle the 
result.  
`.take()` returns a Result union type (explained below) and never fails. It allows for switch semantics and coercion.  
`.takeUnwrapped()` returns an error or a slice. It allows for normal error handling semantics.  
Both methods leave the Future with a dummy 'none' result. It can then be reused.

#### Result Union
Results are tagged unions mainly because I just learned about them.  
They take the form of `MyFutureType.Result.ok: []T`, `MyFutureType.Result.err: anyerror`, and `MyFutureType.Result.none`.

(Note: `.ok` & `.err` are the interesting union tags, while `.none` is due to
my scuffed implementation.)

#### Starting Futures
TODO (see tests in *scry.zig* for examples)

#### Writing Promises
TODO (see tests in *scry.zig* for examples)

