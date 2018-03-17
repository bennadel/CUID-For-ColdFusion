<cfscript>

	cuid = new lib.Cuid();

	// Since CUID for ColdFusion will be running in a multi-threaded environment, we are
	// going to try and simulate contention by spawning multiple asynchronous threads
	// and trying to create thousands of CUID tokens at the same time. Because threads
	// don't spawn immediately, there is no guarantee that this will work; but, it's
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
