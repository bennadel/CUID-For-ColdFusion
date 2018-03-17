<cfscript>

	slug = new lib.Slug();

	// Since SLUG for ColdFusion will be running in a multi-threaded environment, we are
	// going to try and simulate contention by spawning multiple asynchronous threads
	// and trying to create thousands of SLUG tokens at the same time. Because threads
	// don't spawn immediately, there is no guarantee that this will work; but, it's
	// worth a shot.
	goalThreadCount = 10;
	goalSlugCount = 50000;

	for ( i = 0 ; i < 10 ; i++ ) {

		thread
			name = "slug-test-#i#"
			action = "run"
			goalSlugCount = goalSlugCount
			{

			thread.slugs = [];

			for ( var i = 0 ; i < goalSlugCount ; i++ ) {

				arrayAppend( thread.slugs, slug.createSlug() );

			}

		}

	}


	// ------------------------------------------------------------------------------- //
	// ------------------------------------------------------------------------------- //

	startedAt = getTickCount();

	// Block and wait until all the asynchronous threads have completed.
	thread action = "join";

	writeOutput( "Done collecting: " & numberFormat( getTickCount() - startedAt ) & "ms<br />" );

	slugCount = 0;

	// NOTE: Using a HashMap instead of a ColdFusion Struct because ColdFusion seemed
	// to be having some issues managing memory with the struct as it grew - my machine
	// seemed to just get progressively slower, with jstack pointing to struct keys.
	slugTokens = createObject( "java", "java.util.HashMap" )
		.init( javaCast( "int", ( goalThreadCount * goalSlugCount ) ) )
	;

	// Now that all of the CFThreads have re-joined the page, let's iterate over the
	// generated SLUG tokens and see if we found any collisions or anomalies.
	for ( threadName in structKeyArray( cfthread ) ) {

		for ( slugValue in cfthread[ threadName ].slugs ) {

			slugCount++;

			// If the SLUG token has already been recorded, note the conflict.
			if ( structKeyExists( slugTokens, slugValue ) ) {

				writeOutput( "Collision: #slugValue# <br />" );

			}

			slugTokens[ slugValue ] = true;

			// If any of the SLUG values are an unexpected length, stop processing -
			// we need to investigate.
			if ( ( len( slugValue ) < 7 ) || ( len( slugValue ) > 10 ) ) {

				writeOutput( "Invalid length: #slugValue#" );
				abort;

			}

		}

	}

	writeOutput( "Done testing. <br />" );
	writeOutput( "Found: #numberFormat( slugCount )# tokens. <br />" );
	writeOutput( "One last test: " & slug.createSlug() );

</cfscript>
