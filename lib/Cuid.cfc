component
	output = false
	hint = "I generate collision-resistant ids optimized for horizontal scaling and performance (based on cuid by Eric Elliott)."
	{

	/**
	* I initialize the CUID generator. By default, the CUID algorithm uses the JVM to
	* generate the "fingerprint". However, you can provide your own fingerprint. If you
	* do, the fingerprint is expected to be 4-characters (there is no validation).
	* 
	* @fingerprint I am the optional fingerprint to provide (should be 4-characters).
	* @output false
	*/
	public any function init( string fingerprint ) {

		// I am the number of characters used when generating the various blocks. This
		// keeps the CUID length predictable.
		blockSize = 4;

		// I am the radix used to encode numeric values for block generation.
		base = 36;

		// I define the range of valid counter values (before the counter is reset back
		// to zero). By limiting the range to a power of the blockSize, we can ensure
		// that the counter, when formatted baseN, will fit into a string that is at most
		// the same length as the blockSize.
		discreteValues = ( base ^ blockSize );

		// I provide a synchronized integer for the counter. The AtomicInteger allows for
		// better performance over explicit locking when contention is high.
		counter = createObject( "java", "java.util.concurrent.atomic.AtomicInteger" ).init();

		// I am a utility class for manipulating long number values.
		LongClass = createObject( "java", "java.lang.Long" );

		// Since the fingerprint of the host doesn't change over time, we can can 
		// calculate it once and then cache it.
		fingerprintBlock = structKeyExists( arguments, "fingerprint" )
			? rightSize( fingerprint, blockSize )
			: generateFingerprintBlock()
		;

	}

	// ---
	// PUBLIC METHODS.
	// ---

	/**
	* I return a 25-character random string with some collision-busting measures. This
	* value will always start with the letter "c" and is safe to use as a unique server-
	* side record identifier.
	* 
	* @output false
	*/
	public string function createCuid() {

		var timestampBlock = generateTimestampBlock();
		var counterBlock = generateCounterBlock();
		var randomBlock = generateRandomBlock();

		return( "c#timestampBlock##counterBlock##fingerprintBlock##randomBlock#" );

	}

	// ---
	// PRIVATE METHODS.
	// ---

	/**
	* I generate the counter block for the CUID. This value is guaranteed to be the same
	* length as the blockSize.
	* 
	* @output false
	*/
	private string function generateCounterBlock() {

		var value = safeCounter();

		return( rightSize( formatBaseN( value, base ), blockSize ) );

	}


	/**
	* I generate the fingerprint block for the CUID. This value is guaranteed to be 4
	* characters long.
	* 
	* @output false
	*/
	private string function generateFingerprintBlock() {

		var processInfo = getProcessInfo();

		var valueLeft = processInfo.id;
		var valueRight = ( len( processInfo.name ) + base );

		// Reduce the characters in the process name to a single integer.
		for ( var c in listToArray( processInfo.name, "" ) ) {

			valueRight += asc( c );

		}

		return(
			rightSize( formatBaseN( valueLeft, base ), 2 ) &
			rightSize( formatBaseN( valueRight, base ), 2 )
		);

	}


	/**
	* I generate the random block for the CUID. This value is guaranteed to be twice the
	* length of the blockSize.
	* 
	* By using the SHA1 Pseudo-random number generator (SHA1PRNG), rand() will generate
	* a number using the Sun Java SHA1PRNG algorithm. This algorithm provides greater
	* randomness and is more "secure".
	* 
	* @output false
	*/
	private string function generateRandomBlock() {

		var valueLeft = fix( rand( "SHA1PRNG" ) * discreteValues );
		var valueRight = fix( rand( "SHA1PRNG" ) * discreteValues );

		return(
			rightSize( formatBaseN( valueLeft, base ), blockSize ) &
			rightSize( formatBaseN( valueRight, base ), blockSize )
		);

	}


	/**
	* I generate the timestamp block for the CUID. This value is guaranteed to be the
	* same length as the blockSize.
	*
	* @output false
	*/
	private string function generateTimestampBlock() {

		// NOTE: The value returned by getTickCount() can't fit inside an Integer. As 
		// such, we can't use formatBaseN() - we have to use Java's Long class.
		var value = LongClass.toString(
			javaCast( "long", getTickCount() ),
			javaCast( "int", base )
		);

		// Right now, taking the UNIX time and base36-encoding it will result in an
		// 8-character string. And, practically speaking, this will never change in your
		// life-time. However, somewhere around the year 2060, the encoded time will
		// result in a 9-character string. As such, I'm ensuring that the string size
		// will always be 8.
		return( rightSize( value, blockSize * 2 ) );

	}


	/**
	* I return the JVM process info as a struct with "id" and "name" properties. Each
	* property is guaranteed to have length greater than zero.
	* 
	* @output false
	*/
	private struct function getProcessInfo() {

		// For getting the JVM name, I basically took this line right out of Graphcool's
		// Java implementation of cuid.
		// --
		// Read More: https://github.com/graphcool/cuid-java
		var jvmName = createObject( "java", "java.lang.management.ManagementFactory" )
			.getRuntimeMXBean()
				.getName()
		;

		// If the JVM name doesn't contain the "@" with at least one character on either
		// side, then we're going to use a dummy JVM name. This way, we know we'll get
		// two distinct values for PID and host.
		if ( true || ! reFind( ".@.", jvmName ) ) {

			// NOTE: Using a range in order to ensure the dummy ID can be contained
			// within an Integer, otherwise subsequent calls to formatBaseN() may break.
			jvmName = ( randRange( 0, 2147483647 ) & "@host" );

		}

		var processInfo = {
			id: listFirst( jvmName, "@" ),
			name: listRest( jvmName, "@" )
		};

		return( processInfo );

	}


	/**
	* I return the sliced version of the given value, padded with zeros if it isn't long
	* enough to fill the slice.
	* 
	* @output false
	*/
	private string function rightSize(
		required string value,
		required numeric length
		) {

		return( right( "000000000#value#", length ) );

	}


	/**
	* I return the next counter index, resetting the counter if we've reached the end of
	* our discrete value range.
	* 
	* @output false
	*/
	private numeric function safeCounter() {

		// Since CUID can be used across threads, the counter becomes inherently unsafe.
		// As such, we are using an AtomicInteger in order to synchronize access to the
		// counter value. However, instead of incrementing the value forever and 
		// attempting to perform a modulo operation, we are simply covering the range of
		// discrete values and then resetting the counter.
		// --
		// NOTE: Using the while(true) loop with .compareAndSet() was taken from this
		// StackOverflow answer by aioobe, https://stackoverflow.com/a/2960040 .
		while ( true ) {

			var currentValue = counter.get();
			var nextValue = ( currentValue + 1 );

			// If we've reached the end of our discrete values, reset the counter.
			if ( nextValue >= discreteValues ) {

				nextValue = 0;

			}

			// This will only set the new counter value if the counter is currently in
			// a known state; otherwise, the command will be ignored, returning False.
			if ( counter.compareAndSet( javaCast( "int", currentValue ), javaCast( "int", nextValue ) ) ) {

				return( currentValue );

			}

		}

	}

}
