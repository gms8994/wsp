// 'constants' for script - note that Javascript doesn't support real constants, so they can be modified, but don't do it!!!
// user control parameters
var OUTPUT_PLAYLIST_NAME = "WSP output"		// name of playlist to add output songs to
var OUTPUT_SIZE = 950;						// desired size, in MB of output playlist (will always be smaller than this limit)
var UNTRIED_SONG_FRACTION = 0.1;			// fraction of output to set to untried songs (if not enough tried ones, this could be larger)
var RATING_REPEAT_INTERVAL = 7; 			// repeat interval, in days, per rating tick (r = 100: 1 * interval, r = 99: 2 * interval, etc.   r = 1: 100 * interval, note r = 0 means unrated )
var SKIP_LEARN_RATE = 0.9; 					// when skipped, new rating is set to old_rating + (new_rating-old_rating) * skip_learn_rate
var PLAY_LEARN_RATE = 0.3; 					// when played, new rating is set to old_rating + (new_rating-old_rating) * play_learn_rate
var PLAYED_FIRST_TIME_RATING = 100; 		// since there's no time period the first time a song is attempted, what rating do I use if it's played?
var SKIPPED_FIRST_TIME_RATING = 90; 		// since there's no time period the first time a song is attempted, what rating do I use if it's skipped?

// advanced control parameters; not much reason to adjust these
var TRIED_SONGS = "WSP4 Tried";				// playlist of songs with previous attempts (play & skip dates give us soemthing to work with)
var UNTRIED_SONGS = "WSP4 Untried";			// songs that have never been attempted (no play & skip dates)




// create date from Itunes, checking if it is invalid and if so, returning one far in the past instead to simplify comparisons
function GetDate( itunes_date )
{
	return new Date( itunes_date )
}



// song class
function Song( track, last_attempted_date )
{
	this.itunes_track = track;										// iTunes song
	this.size = track.size;
	
	var rating = track.rating;
	var elapsed_time = currDate - last_attempted_date;

	var multiplier = RATING_REPEAT_INTERVAL * (101-rating);			// in theory, RATING_REPEAT_INTERVAL can be omitted since it's only a relative comparison vs. other songs

	this.play_pressure = elapsed_time / multiplier;					// pressure for being played
};



function WriteSongs( output_songs )
{
	// grab output playlist
	outputPlaylist = iTunesApp.LibrarySource.Playlists.ItemByName( OUTPUT_PLAYLIST_NAME );

	if( outputPlaylist )
	{
		// clear it out, must be a better way, but this is the only method I am aware of - not much documentation
		var old_tracks = outputPlaylist.Tracks;
		var remo = [];
		for( i = 1; i <= old_tracks.Count; i++ )
		{
			var currTrack = old_tracks.Item( i );
			remo.push( currTrack );
		}
		for( var q=0; q < remo.length; q++ )
		{
			remo[q].Delete();
		}
	}
	else
	{
		// doesn't exist, so create
		outputPlaylist = iTunesApp.CreatePlaylist( OUTPUT_PLAYLIST_NAME );
	}
	

	// add tracks to output playlist
	for( var i = 0; i < output_songs.length; i++ )
	{
		outputPlaylist.AddTrack( output_songs[i] );
	}
}



// get songs that have never been attempted before
function GetUntriedSongs( songs )
{
	// open untried song playlist
	WSP_untried = iTunesApp.LibrarySource.Playlists.ItemByName( UNTRIED_SONGS );
	var untried_tracks = WSP_untried.Tracks;
	var untried_target_size = OUTPUT_SIZE * UNTRIED_SONG_FRACTION;

	var size = 0;
	
	var numTracks = untried_tracks.Count;
	for( i = 1; i <= numTracks; i++ )
	{
		try
		{
			var track = untried_tracks.Item( i );
			var song_size = track.size;
			
			if( size + song_size > untried_target_size )
				break;
			
			songs.push( track );
			size += song_size;
		}
		catch( er )
		{
		}
	}
	
	return size;
}



// extract last attempted date from comment of traclk, returns null if none
function GetLastAttemptedDate( track )
{
	var com = track.Comment;
	
	var identLoc = com.indexOf("WSP LAD: ");
	
	if( identLoc == -1 )
		return null;
	
	var last_atttempted_date_string = com.substr( identLoc+9, 19 );
	var last_attempted_date = new Date( last_atttempted_date_string );
	
	return last_attempted_date;
}



// convert date into sortable date and time
function DateToSortableString( date )
{
	var year = date.getFullYear();
	var month = date.getMonth()+1;
	var day = date.getDate();
	var hours = date.getHours();
	var minutes = date.getMinutes();
	var seconds = date.getSeconds();
	var sort_string = year.toString() + "/";
	if( month < 10 )
		sort_string += "0";
	sort_string += month.toString() + "/";
	if( day < 10 )
		sort_string += "0";
	sort_string += day.toString() + " ";
	if( hours < 10 )
		sort_string += "0";
	sort_string += hours.toString() + ":";
	if( minutes < 10 )
		sort_string += "0";
	sort_string += minutes.toString() + ":";
	if( seconds < 10 )
		sort_string += "0";
	sort_string += seconds.toString();
	
	return sort_string;
}



// get last attempted date and update track rating based on plays & skips
function UpdateTrackInfo( track )
{
	var play_date = GetDate( track.PlayedDate );
	var skip_date = GetDate( track.SkippedDate );
	var last_attempted_date = GetLastAttemptedDate( track );

	// determine most recent of play or skip date
	var new_attempt_date = play_date;
	
	if( skip_date > new_attempt_date )
		new_attempt_date = skip_date;

	if( last_attempted_date == null )
	{
		// if no rating already, set to default first time guess
		var old_rating = track.rating;
		
		if( old_rating == 0 )
		{
			// first attempt in the system, use default ratings
			if( play_date >= skip_date )
				track.rating = PLAYED_FIRST_TIME_RATING;
			else
				track.rating = SKIPPED_FIRST_TIME_RATING;
		}
		
		// no stored last attempted date, write new one
		track.Comment = "WSP LAD: " + DateToSortableString( new_attempt_date );
	}
	else if( new_attempt_date > last_attempted_date )
	{
		// new attempt was made
		if( play_date > last_attempted_date )
		{
			if( skip_date < last_attempted_date )
			{
				// play, see if rating should be increased
				var elapsed_time = new_attempt_date - last_attempted_date;

				var new_rating = Math.floor( 101 - elapsed_time / RATING_REPEAT_INTERVAL );
				
				var old_rating = track.rating;

				if( new_rating > old_rating )
					track.rating = Math.round( old_rating + (new_rating - old_rating)*PLAY_LEARN_RATE );
			}
		}
		else
		{
			// skip, see if rating should be decreased
			var elapsed_time = new_attempt_date - last_attempted_date;

			// compute rounded rating
			var new_rating = Math.floor( 101 - elapsed_time / RATING_REPEAT_INTERVAL );

			if( new_rating < 1 )
				new_rating = 1;
			
			var old_rating = track.rating;

			if( new_rating < old_rating )
				track.rating = Math.round( old_rating + (new_rating - old_rating)*SKIP_LEARN_RATE );
		}
		
		// write new attemtped date
		track.Comment = "WSP LAD: " + DateToSortableString( new_attempt_date );
	}
	
	return new_attempt_date;
}



// sort songs by decreasing play pressure
function SortByPlayPressure( songs )
{
	// sort songs
	songs.sort(function(a, b){return b.play_pressure - a.play_pressure});
}



// select the songs with the greatetst play pressure
function GetHighestPressureSongs( chosen_tracks, all_songs, target_size )
{
	// sort songs by decreasing play pressure
	SortByPlayPressure( all_songs );
	
	// add to selected tracks until target size is reached
	var size = 0;
	for( var i=0; i < all_songs.length; i++ )
	{
		if( size + all_songs[i].size > target_size )
			break;
		
		size += all_songs[i].size
		chosen_tracks.push( all_songs[i].itunes_track );
	}
}



// get songs that have been attempted before, and process songs with new information
function GetTriedSongs( chosen_tracks, target_size )
{
	// open tried song playlist
	WSP_tried = iTunesApp.LibrarySource.Playlists.ItemByName( TRIED_SONGS );
	var tried_tracks = WSP_tried.Tracks;
	
	var songs = [];				// array of song objects (has a play pressure for each)
	
	// create song object for each track, and process new information
	var numTracks = tried_tracks.Count;
	for( var i = 1; i <= numTracks; i++ )
	{
		try
		{
			var track = tried_tracks.Item( i );

			// see if a play attempt has been made since last time script was run or if song is new to the music system
			var last_attempted_date = UpdateTrackInfo( track );

			var newSong = new Song( track, last_attempted_date );
			
			// create song object, which computes play pressure
			songs.push( newSong );
		}
		catch( er )
		{
		}
	}

	// choose songs with the highest pressure for output
	GetHighestPressureSongs( chosen_tracks, songs, target_size );
}

	

function GetSongsToAdd()
{
	var songs = [];
	
	// get untried songs (if any)
	var untried_size = GetUntriedSongs( songs );
	
	// get tried songs to fill up rest of playlist, and process songs with new information
	GetTriedSongs( songs, OUTPUT_SIZE - untried_size );
	
	return songs;
}








// conversions to iTunes units
RATING_REPEAT_INTERVAL *= 24.0* 3600.0 * 1000.0;	// convert to milliseconds
OUTPUT_SIZE *= 1024 * 1024;							// convert to bytes


// get today's time
var currDate = new Date();

var iTunesApp = WScript.CreateObject( "iTunes.Application" );


if( iTunesApp )
{
	// get songs to be added to output playlist, updating attempted and new ones in the process
	var output_songs = GetSongsToAdd();
	
	// write songs to output playlist
	WriteSongs( output_songs );
}

















