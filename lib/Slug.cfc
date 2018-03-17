component
	output = false
	hint = "I generate small collision-resistant ids for trivial tasks like URL disambiguation (based on cuid.slug() by Eric Elliott)."
	{

	/**
	* I initialize the SLUG generator. By default, the SLUG algorithm uses the JVM to
	* generate the "fingerprint". However, you can provide your own fingerprint. If you
	* do, the fingerprint is limited to be 2-characters (there is no validation).
	* 
	* @fingerprint I am the optional fingerprint to provide (should be 2-characters).
	* @output false
	*/
	public any function init( string fingerprint ) {

		// I am the radix used to encode numeric values for block generation.
		base = 36;

		// I define the range of valid counter values (before the counter is reset back
		// to zero). By limiting the range to a power of 4, we can ensure that the
		// counter, when formatted baseN, will fit into a string that is at most 4
		// characters long.
		discreteValues = ( base ^ 4 );

		// I provide a synchronized integer for the counter. The AtomicInteger allows for
		// better performance over explicit locking when contention is high.
		counter = createObject( "java", "java.util.concurrent.atomic.AtomicInteger" ).init();

		// I am a utility class for manipulating long number values.
		LongClass = createObject( "java", "java.lang.Long" );

		// Since the fingerprint of the host doesn't change over time, we can can 
		// calculate it once and then cache it.
		fingerprintBlock = structKeyExists( arguments, "fingerprint" )
			? left( fingerprint, 2 )
			: generateFingerprintBlock()
		;

	}

	// ---
	// PUBLIC METHODS.
	// ---

	/**
	* I return a random string between 7 and 10 characters (inclusive) with some
	* collision-busting measures. The string will only contain alpha-numeric characters.
	* 
	* CAUTION: This is not intended to be as random or as secure as the CUID and
	* should NOT BE USED for server-side record identifiers or any situation in which
	* it would be problematic for the generated value to be guessable.
	* 
	* @output false
	*/
	public string function createSlug() {

		var timestampBlock = generateTimestampBlock();
		var counterBlock = generateCounterBlock();
		var randomBlock = generateRandomBlock();

		return( "#timestampBlock##counterBlock##fingerprintBlock##randomBlock#" );

	}

	// ---
	// PRIVATE METHODS.
	// ---

	/**
	* I generate the counter block for the SLUG. This value will be between 1 and 4
	* characters long (inclusive), as the counter increases.
	* 
	* @output false
	*/
	private string function generateCounterBlock() {

		var value = safeCounter();

		return( right( formatBaseN( value, base ), 4 ) );

	}


	/**
	* I generate the fingerprint block for the SLUG. This value is guaranteed to be 2
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
			left( formatBaseN( valueLeft, base ), 1 ) &
			right( formatBaseN( valueRight, base ), 1 )
		);

	}


	/**
	* I generate the random block for the SLUG. This value is guaranteed to be 2
	* characters long.
	* 
	* By using the SHA1 Pseudo-random number generator (SHA1PRNG), rand() will generate
	* a number using the Sun Java SHA1PRNG algorithm. This algorithm provides greater
	* randomness and is more "secure".
	* 
	* @output false
	*/
	private string function generateRandomBlock() {

		var value = fix( rand( "SHA1PRNG" ) * 1000 );
		var encodedValue = formatBaseN( value, base );

		return( right( "0#encodedValue#", 2 ) );

	}


	/**
	* I generate the timestamp block for the SLUG. This value is guaranteed to be 2
	* characters long.
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

		return( right( value, 2 ) );

	}


	/**
	* I return the JVM process info as a struct with "id" and "name" properties. Each
	* property is guaranteed to have length greater than zero and the "id" is guaranteed
	* to be a number.
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

		// Sanitize the ID to make sure that it's a number that fits into an integer.
		processInfo.id = abs( val( processInfo.id ) );
		processInfo.id = min( processInfo.id, 2147483647 );

		return( processInfo );

	}


	/**
	* I return the next counter index, resetting the counter if we've reached the end of
	* our discrete value range.
	* 
	* @output false
	*/
	private numeric function safeCounter() {

		// Since SLUG can be used across threads, the counter becomes inherently unsafe.
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
