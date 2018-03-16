
# cuid For ColdFusion

by [Ben Nadel][bennadel] (on [Google+][googleplus])

**Version 1.0.0**

This is a **ColdFusion port** of the [node.js cuid library][cuid] originally authored by
[Eric Elliott][ericelliott]. It provides collision-resistant ids that are optimized for
horizontal scaling and binary search lookup performance.

Each cuid value starts with the letter `c` and contains only alpha-numeric characters,
making it safe to use as both an HTML element's ID attribute and as a server-side record
identifier. The length of the cuid is guaranteed to be 25-characters (in this ColdFusion
implementation).

> **ASIDE**: The original cuid library makes no guarantees about length. However, it will
> coincidentally generate cuid tokens that are 25-characters long. This is because the
> `Date.now()` timestamp is currently base36-encoded as 8-characters. However, somewhere
> around the **year 2060**, a base36-encoding of `Date.now()` will start returning a
> 9-character string, bumping the length of the cuid up to 26-characters.

The cuid library for ColdFusion is **thread safe** and is intended to be instantiated
once within an application and cached for future usage. The cuid library exposes one
public method, `.createCuid()`, which will generate and return your cuid token:

```cfc
// Create and cache the instance for use across all requests in the application.
application.cuid = new lib.Cuid();

// Generate as many cuid values as you want! Skies the limit! Go cra-cra!
writeOutput( "cuid: " & application.cuid.createCuid() & "<br />" );
writeOutput( "cuid: " & application.cuid.createCuid() & "<br />" );
writeOutput( "cuid: " & application.cuid.createCuid() & "<br />" );
writeOutput( "cuid: " & application.cuid.createCuid() & "<br />" );

```

Running the above code will produce the following output:

```txt
cuid: cjetsjdk40000ecdihhc50anj
cuid: cjetsjdk40001ecdij952y404
cuid: cjetsjdk40002ecdil65fefyh
cuid: cjetsjdk40003ecdit3o3usnj
```

To understand the segments contained within the cuid, please refer to the [original
documentation][cuid].

## Custom Fingerprints

By default, the cuid for ColdFusion library will generate a fingerprint based on the name
of the JVM (which I borrowed from the [cuid for Graphcool][graphcool] implementation).
However, you can pass in a custom fingerprint during instantiation if you want:

```cfc
var cuid = new lib.Cuid( "lolz" );

writeOutput( cuid.createCuid() ); // Outputs: cjetszc2wapswlolz29ev17go
```

Other than ensuring that the custom fingerprint is "block sized", the cuid for ColdFusion
library makes no other alterations and performs no other validation. As such, be careful
what you use as a _custom_ fingerprint.

## No `slug()` Method

At this time, the cuid for ColdFusion library omits the `slug()` method that is present
in the original node.js version. I am omitting it simply because it feels like a separate
concern and not sufficiently related to cuid generation.

## Proof Of Concept

The cuid library is collision **resistant**, not necessarily collision **proof**.
However, the chances of generating a collision are intensely small. To try and test this
property of the library, I created a script that runs 10 asynchronous CFThread blocks
that all generate 50,000 cuid tokens. The script then waits for all the threads to return
and checks to see if any duplicate or malformed tokens were created:

```cfc
<cfscript>

	cuid = new lib.Cuid();

	// Since CUID for ColdFusion will be running in a multi-threaded environment, we are
	// going to try and simulate contention by spawning multiple asynchronous threads
	// and trying to create thousands of CUID tokens at the same time. Because threads
	// don't spawn immediately, there is not guarantee that this will work; but, it's
	// worth a shot.
	goalThreadCount = 10;
	goalCuidCount = 50000;

	for ( i = 0 ; i < 10 ; i++ ) {

		thread
			name = "cuid-test-#i#"
			action = "run"
			goalCuidCount = goalCuidCount
			{

			thread.cuids = [];

			for ( var i = 0 ; i < goalCuidCount ; i++ ) {

				arrayAppend( thread.cuids, cuid.createCuid() );

			}

		}

	}


	// ------------------------------------------------------------------------------- //
	// ------------------------------------------------------------------------------- //

	startedAt = getTickCount();

	// Block and wait until all the asynchronous threads have completed.
	thread action = "join";

	writeOutput( "Done collecting: " & numberFormat( getTickCount() - startedAt ) & "ms<br />" );

	cuidCount = 0;

	// NOTE: Using a HashMap instead of a ColdFusion Struct because ColdFusion seemed
	// to be having some issues managing memory with the struct as it grew - my machine
	// seemed to just get progressively slower, with jstack pointing to struct keys.
	cuidTokens = createObject( "java", "java.util.HashMap" )
		.init( javaCast( "int", ( goalThreadCount * goalCuidCount ) ) )
	;

	// Now that all of the CFThreads have re-joined the page, let's iterate over the
	// generated CUID tokens and see if we found any collisions or anomalies.
	for ( threadName in structKeyArray( cfthread ) ) {

		for ( cuidValue in cfthread[ threadName ].cuids ) {

			cuidCount++;

			// If the CUID token has already been recorded, note the conflict.
			if ( structKeyExists( cuidTokens, cuidValue ) ) {

				writeOutput( "Collision: #cuidValue# <br />" );

			}

			cuidTokens[ cuidValue ] = true;

			// If any of the CUID values are an unexpected length, stop processing -
			// we need to investigate.
			if ( len( cuidValue ) != 25 ) {

				writeOutput( "Invalid length: #cuidValue#" );
				abort;

			}

		}

	}

	writeOutput( "Done testing. <br />" );
	writeOutput( "Found: #numberFormat( cuidCount )# tokens. <br />" );
	writeOutput( "One last test: " & cuid.createCuid() );

</cfscript>
```

As you can see, this attempts to create 500,000 cuid values in parallel. And, when we run
the above code, we get the following output:

```txt
Done collecting: 3,865ms
Done testing. 
Found: 500,000 tokens. 
One last test: cjetsqji0apsw7cdivy9oogi9
```

Not only can the cuid for ColdFusion library produce 500,000 cuid tokens in just a few
seconds, none of them collide and none of them are malformed.


[bennadel]: http://www.bennadel.com
[cuid]: https://github.com/ericelliott/cuid
[ericelliott]: https://medium.com/@_ericelliott
[googleplus]: https://plus.google.com/108976367067760160494?rel=author
[graphcool]: https://github.com/graphcool/cuid-java
