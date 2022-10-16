//
// Copyright © 2022 Sebastian Hetze (shetze)
//
// This plugin is free software: you can redistribute it and/or modify
// it under the terms of the GNU Lesser General Public License as published
// by the Free Software Foundation, either version 2.1 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU Lesser General Public License
// along with this program.  If not, see <http://www.gnu.org/licenses/>.
//
// This plugion makes use of some techniques demonstrated by the MuseScore
// example plugins. No copyright is claimed for these or the API extracts.
//

import QtQuick 2.9;
import QtQuick.Controls 1.4;
import QtQuick.Layouts 1.3;
import QtQuick.Dialogs 1.2;
import Qt.labs.settings 1.0;
// FileDialog
import Qt.labs.folderlistmodel 2.2;
import QtQml 2.8;
import MuseScore 3.0;
import FileIO 3.0;

MuseScore
{
description:"Export to FrapTools Usta Sequencer";
menuPath:"Plugins." + "Frap Usta Export";
version:"1.2";
requiresScore:true;
pluginType:"dialog";
id:window;
width:800;
height:250;

  property int buttonWidth:80;
  property int smallWidth:150;
  property int mediumWidth:300;
  property int bigWidth:500;
  property int stdHeight:24;
  property int bigHeight:45;
  property int fontTitleSize:16;
  property int fontSize:12;
  property string crlf:"\r\n";
  property var patternDict:[];
  property var patterns:["T0_CVA_values", "T0_CVB_values",
			 "T0_CVA_var_mode_len", "T0_CVB_var_mode", "T0_GTA",
			 "T0_GTB", "T1_CVA_values", "T1_CVB_values",
			 "T1_CVA_var_mode_len", "T1_CVB_var_mode", "T1_GTA",
			 "T1_GTB", "T2_CVA_values", "T2_CVB_values",
			 "T2_CVA_var_mode_len", "T2_CVB_var_mode", "T2_GTA",
			 "T2_GTB", "T3_CVA_values", "T3_CVB_values",
			 "T3_CVA_var_mode_len", "T3_CVB_var_mode", "T3_GTA",
			 "T3_GTB"];
  property var sinfonionDict:[];
  property var patternsPerMeasure:[1, 1, 1, 1, 1, 1, 1, 1];
  property var maxVoiceId:0;
  property var voiceLimit:1;
  property var maxStaffId:0;
  property var staffLimit:3;
  property var staffMerge:0;
  property var tempoBPM:[0, 0, 0, 0];
  // MIDI note 0 is C-2@8.176Hz
  // Usta has a pitch range starting with 0V named either C0 or A0, negative CV
  // values are not supported for pitch. To match the MuseScore note values with
  // the Usta range, we ignore the two lowest octaves and shift the MIDI note
  // values 24 semitones down.
  property var midiShift:24;

  // buildMeasureMap() calculates the metrics of the score into the map dict
  // structure to provide some context in further passes through the score
  function buildMeasureMap (score)
  {
    var map = { };
    var no = 1;
    var cursor = score.newCursor ();
    cursor.rewind (Cursor.SCORE_START);
    while (cursor.measure)
      {
	var m = cursor.measure;
	var tick = m.firstSegment.tick;
	var tsD = m.timesigActual.denominator;
	var tsN = m.timesigActual.numerator;
	var ticksB = division * 4.0 / tsD;
	var ticksM = ticksB * tsN;
	no += m.noOffset;
	var cur = {
	"tick":tick,
	"tsD":tsD,
	"tsN":tsN,
	"ticksB":ticksB,
	"ticksM":ticksM,
	"past":(tick + ticksM),
	"no":no
	};
	map[cur.tick] = cur;
	if (!m.irregular)
	  ++no;
	// get an overview of how many voices and staves we have in the score
	if (cursor.staffIdx > maxStaffId)
	  maxStaffId = cursor.staffIdx;
	if (cursor.voice > maxVoiceId)
	  maxVoiceId = cursor.voice;

	// collect tempo BPM settings throughout the score.
	// the first (global) BPM setting is populated as default, all other
	// settings are stored for the respective save index, allowing for
	// different tempo settings for the four Usta tracks.
	var segment = m.firstSegment;
	while ((segment != null)
	       && (segment.segmentType != Segment.ChordRest))
	  {
	    // console.log('Walking through segments, looking for first chord
	    // or rest');
	    segment = segment.nextInMeasure;
	  }
	if (segment != null)
	  {
	    for (var i = segment.annotations.length; i-- > 0;)
	      {
		// console.log('walking through annotations');
		if (segment.annotations[i].type == Element.TEMPO_TEXT)
		  {
		    if (segment.annotations[i].tempo != 0)
		      {
			if (tempoBPM[0] == 0)
			  {
			    tempoBPM[0] = segment.annotations[i].tempo * 60;
			    tempoBPM[1] = segment.annotations[i].tempo * 60;
			    tempoBPM[2] = segment.annotations[i].tempo * 60;
			    tempoBPM[3] = segment.annotations[i].tempo * 60;
			  }
			else
			  {
			    // TEMPO_TEXT annotations allways belong to the
			    // first voice of the first staff
			    // therefor only the first track tempo can be
			    // modified by additional TEMPO_TEXT settings.
			    tempoBPM[cursor.staffIdx] =
			      segment.annotations[i].tempo * 60;
			  }
		      }
		    console.log ('found tempo ' + tempoBPM[cursor.staffIdx]);
		    break;
		  }

		// staff text annotations provide an easy and flexible way to
		// pass all kinds of global and per track settings
		// although the staff text is visibly attached to a particular
		// line,
		if (segment.annotations[i].type == Element.STAFF_TEXT)
		  {
		    // console.log('found staff text ' + cursor.staffIdx + ':'
		    // + segment.annotations[i].text.slice(0,4));
		    // to allow individual tempo settings for all four staves,
		    // we look for "BPM=x:yyy" staff text annotations
		    // where x is the track number (0-3) and yyy is the BPM
		    // value
		    if (segment.annotations[i].text.slice (0, 4) == "BPM=")
		      {
			var staffIdx =
			  segment.annotations[i].text.slice (4, 5);
			tempoBPM[staffIdx] =
			  segment.annotations[i].text.slice (6, 9);
			console.log ('found staff text BPM ' + staffIdx +
				     ':' + tempoBPM[staffIdx]);
		      }
		  }
		if (segment.annotations[i].type == Element.HARMONY)
		  {
		    var sinfony =
		      chord2Sinfonion (segment.annotations[i].text,
				       (4 * ticksM / 480));
		    console.log ('found accord symbol ' + tsN + "/" + tsD +
				 " measure " + no + " at tick " + cur.tick +
				 " length " + ticksM + ':' +
				 segment.annotations[i].text + "->" +
				 sinfony);
		  }
	      }
	  }
	// console.log(tsN + "/" + tsD + " measure " + no + " at tick " +
	// cur.tick + " length " + ticksM);
	cursor.nextMeasure ();
      }
    return map;
  }

  // applyToSelectionOrScore(cb, ...args) is the workhorse which walks
  // through the current score or selection thereof element by element and
  // applies a callback function with possible args
  function applyToSelectionOrScore (cb)
  {
    var args = Array.prototype.slice.call (arguments, 1);
    var staveBeg;
    var staveEnd;
    var tickEnd;
    var rewindMode;
    var toEOF;

    var cursor = curScore.newCursor ();
    cursor.rewind (Cursor.SELECTION_START);
    if (cursor.segment)
      {
	staveBeg = cursor.staffIdx;
	cursor.rewind (Cursor.SELECTION_END);
	staveEnd = cursor.staffIdx;
	if (!cursor.tick)
	  {
	    /*
	     * This happens when the selection goes to the
	     * end of the score — rewind() jumps behind the
	     * last segment, setting tick = 0.
	     */
	    toEOF = true;
	  }
	else
	  {
	    toEOF = false;
	    tickEnd = cursor.tick;
	  }
	rewindMode = Cursor.SELECTION_START;
      }
    else
      {
	/* no selection */
	staveBeg = 0;
	staveEnd = curScore.nstaves - 1;
	toEOF = true;
	rewindMode = Cursor.SCORE_START;
      }

    for (var stave = staveBeg; stave <= staveEnd; ++stave)
      {
	for (var voice = 0; voice < 4; ++voice)
	  {
	    cursor.staffIdx = stave;
	    cursor.voice = voice;
	    cursor.rewind (rewindMode);
	    /* XXX https://musescore.org/en/node/301846 */
	    cursor.staffIdx = stave;
	    cursor.voice = voice;

	    while (cursor.segment && (toEOF || cursor.tick < tickEnd))
	      {
		if (cursor.element)
		  cb.apply (null,[cursor].concat (args));
		cursor.next ();
	      }
	  }
      }
  }

  // showPos is a debugging function which makes use of the measureMap metrics
  // to position the current event inside the staff/voice/measure space
  function showPos (cursor, measureMap)
  {
    var t = cursor.segment.tick;
    var m = measureMap[cursor.measure.firstSegment.tick];
    var b = "?";
    if (m && t >= m.tick && t < m.past)
      {
	b = 1 + (t - m.tick) / m.ticksB;
      }

    return "St" + (cursor.staffIdx + 1) +
      " Vc" + (cursor.voice + 1) + " Ms" + m.no + " Bt" + b;
  }

  // matchGrid checks if the cursor is matching a 16th note grid pattern
  function matchGrid (cursor, measureMap)
  {
    var t = cursor.segment.tick;
    var m = measureMap[cursor.measure.firstSegment.tick];
    var b = 0;
    if (m && t >= m.tick && t < m.past)
      {
	b = ((t - m.tick) / m.ticksB) % 0.25;
      }
    if (b > 0)
      {
	return 0;
      }
    return 1;
  }

  // nameElementType() knows about all the possible elements that can appear
  // inside a score. Currently, we only care about CHORD and REST, but this may
  // change in the future.
  function nameElementType (elementType)
  {
    switch (elementType)
      {
      case Element.ACCIDENTAL:
	return "ACCIDENTAL";
      case Element.AMBITUS:
	return "AMBITUS";
      case Element.ARPEGGIO:
	return "ARPEGGIO";
      case Element.ARTICULATION:
	return "ARTICULATION";
      case Element.BAGPIPE_EMBELLISHMENT:
	return "BAGPIPE_EMBELLISHMENT";
      case Element.BAR_LINE:
	return "BAR_LINE";
      case Element.BEAM:
	return "BEAM";
      case Element.BEND:
	return "BEND";
      case Element.BRACKET:
	return "BRACKET";
      case Element.BRACKET_ITEM:
	return "BRACKET_ITEM";
      case Element.BREATH:
	return "BREATH";
      case Element.CHORD:
	return "CHORD";
      case Element.CHORDLINE:
	return "CHORDLINE";
      case Element.CLEF:
	return "CLEF";
      case Element.COMPOUND:
	return "COMPOUND";
      case Element.DYNAMIC:
	return "DYNAMIC";
      case Element.ELEMENT:
	return "ELEMENT";
      case Element.ELEMENT_LIST:
	return "ELEMENT_LIST";
      case Element.FBOX:
	return "FBOX";
      case Element.FERMATA:
	return "FERMATA";
      case Element.FIGURED_BASS:
	return "FIGURED_BASS";
      case Element.FINGERING:
	return "FINGERING";
      case Element.FRET_DIAGRAM:
	return "FRET_DIAGRAM";
      case Element.FSYMBOL:
	return "FSYMBOL";
      case Element.GLISSANDO:
	return "GLISSANDO";
      case Element.GLISSANDO_SEGMENT:
	return "GLISSANDO_SEGMENT";
      case Element.HAIRPIN:
	return "HAIRPIN";
      case Element.HAIRPIN_SEGMENT:
	return "HAIRPIN_SEGMENT";
      case Element.HARMONY:
	return "HARMONY";
      case Element.HBOX:
	return "HBOX";
      case Element.HOOK:
	return "HOOK";
      case Element.ICON:
	return "ICON";
      case Element.IMAGE:
	return "IMAGE";
      case Element.INSTRUMENT_CHANGE:
	return "INSTRUMENT_CHANGE";
      case Element.INSTRUMENT_NAME:
	return "INSTRUMENT_NAME";
      case Element.JUMP:
	return "JUMP";
      case Element.KEYSIG:
	return "KEYSIG";
      case Element.LASSO:
	return "LASSO";
      case Element.LAYOUT_BREAK:
	return "LAYOUT_BREAK";
      case Element.LEDGER_LINE:
	return "LEDGER_LINE";
      case Element.LET_RING:
	return "LET_RING";
      case Element.LET_RING_SEGMENT:
	return "LET_RING_SEGMENT";
      case Element.LYRICS:
	return "LYRICS";
      case Element.LYRICSLINE:
	return "LYRICSLINE";
      case Element.LYRICSLINE_SEGMENT:
	return "LYRICSLINE_SEGMENT";
      case Element.MARKER:
	return "MARKER";
      case Element.MEASURE:
	return "MEASURE";
      case Element.MEASURE_LIST:
	return "MEASURE_LIST";
      case Element.MEASURE_NUMBER:
	return "MEASURE_NUMBER";
      case Element.NOTE:
	return "NOTE";
      case Element.NOTEDOT:
	return "NOTEDOT";
      case Element.NOTEHEAD:
	return "NOTEHEAD";
      case Element.NOTELINE:
	return "NOTELINE";
      case Element.OSSIA:
	return "OSSIA";
      case Element.OTTAVA:
	return "OTTAVA";
      case Element.OTTAVA_SEGMENT:
	return "OTTAVA_SEGMENT";
      case Element.PAGE:
	return "PAGE";
      case Element.PALM_MUTE:
	return "PALM_MUTE";
      case Element.PALM_MUTE_SEGMENT:
	return "PALM_MUTE_SEGMENT";
      case Element.PART:
	return "PART";
      case Element.PEDAL:
	return "PEDAL";
      case Element.PEDAL_SEGMENT:
	return "PEDAL_SEGMENT";
      case Element.REHEARSAL_MARK:
	return "REHEARSAL_MARK";
      case Element.REPEAT_MEASURE:
	return "REPEAT_MEASURE";
      case Element.REST:
	return "REST";
      case Element.SCORE:
	return "SCORE";
      case Element.SEGMENT:
	return "SEGMENT";
      case Element.SELECTION:
	return "SELECTION";
      case Element.SHADOW_NOTE:
	return "SHADOW_NOTE";
      case Element.SLUR:
	return "SLUR";
      case Element.SLUR_SEGMENT:
	return "SLUR_SEGMENT";
      case Element.SPACER:
	return "SPACER";
      case Element.STAFF:
	return "STAFF";
      case Element.STAFFTYPE_CHANGE:
	return "STAFFTYPE_CHANGE";
      case Element.STAFF_LINES:
	return "STAFF_LINES";
      case Element.STAFF_LIST:
	return "STAFF_LIST";
      case Element.STAFF_STATE:
	return "STAFF_STATE";
      case Element.STAFF_TEXT:
	return "STAFF_TEXT";
      case Element.STEM:
	return "STEM";
      case Element.STEM_SLASH:
	return "STEM_SLASH";
      case Element.STICKING:
	return "STICKING";
      case Element.SYMBOL:
	return "SYMBOL";
      case Element.SYSTEM:
	return "SYSTEM";
      case Element.SYSTEM_DIVIDER:
	return "SYSTEM_DIVIDER";
      case Element.SYSTEM_TEXT:
	return "SYSTEM_TEXT";
      case Element.TAB_DURATION_SYMBOL:
	return "TAB_DURATION_SYMBOL";
      case Element.TBOX:
	return "TBOX";
      case Element.TEMPO_TEXT:
	return "TEMPO_TEXT";
      case Element.TEXT:
	return "TEXT";
      case Element.TEXTLINE:
	return "TEXTLINE";
      case Element.TEXTLINE_BASE:
	return "TEXTLINE_BASE";
      case Element.TEXTLINE_SEGMENT:
	return "TEXTLINE_SEGMENT";
      case Element.TIE:
	return "TIE";
      case Element.TIE_SEGMENT:
	return "TIE_SEGMENT";
      case Element.TIMESIG:
	return "TIMESIG";
      case Element.TREMOLO:
	return "TREMOLO";
      case Element.TREMOLOBAR:
	return "TREMOLOBAR";
      case Element.TRILL:
	return "TRILL";
      case Element.TRILL_SEGMENT:
	return "TRILL_SEGMENT";
      case Element.TUPLET:
	return "TUPLET";
      case Element.VBOX:
	return "VBOX";
      case Element.VIBRATO:
	return "VIBRATO";
      case Element.VIBRATO_SEGMENT:
	return "VIBRATO_SEGMENT";
      case Element.VOLTA:
	return "VOLTA";
      case Element.VOLTA_SEGMENT:
	return "VOLTA_SEGMENT";
      default:
	return "(Element." + (elementType + 0) + ")";
      }
  }

  // dirname() takes a path/filename and returns the path part
  function dirname (p)
  {
    return (p.slice (0, p.lastIndexOf ("/") + 1));
  }

  // FileIO is the QT object which handles all the heavy lifting
  FileIO
  {
  id:csvWriter;
  onError:console.log (msg + "  Filename = " + csvWriter.source);
  }

  // createCSV() is the actual export method in which the usta sequencer
  // project data is compiled and written into a file.
  // The project consists of four parts; the songs part, a per track settings
  // part, 4*5 lines of patterns and a closing part with global settings.
  function createCSV ()
  {

    if (!textFieldFileName.text)
      {
	errorDialog.openErrorDialog (qsTr ("File name not specified"));
	return;
      }
    else if (!textFieldFilePath.text)
      {
	errorDialog.openErrorDialog (qsTr ("File folder not specified"));
	return;
      }
    if (textFieldFileName.text == ".UST")
      textFieldFileName.text = "SCORE.UST";
    var csv = "";

    csv += createSongs ();
    csv += createPerTrackSettings ();
    csv += dumpPatterns ();
    csv += createGlobalSettings ();
    var filename = textFieldFilePath.text + "/" + textFieldFileName.text;
    console.log ("export to " + filename);
    csvWriter.source = filename;
    console.log ("writing csv...");
    csvWriter.write (csv);
    console.log ("conversion performed");
    endDialog.open ();
  }

  // createSongs() is generating four lines of default (empty) song structures
  // we may want to add some more features here in the future
  // a random song generator may be interesting
  function createSongs ()
  {
    console.log ("compiling the Song section...");
    var song = "";
    for (var s = 0; s < 4; s++)
      {
	for (var i = 0; i < 130; i++)
	  {
	    if (i == 65)
	      song += "1;";
	    else
	      song += "0;";
	  }
	song += "SONG " + s + crlf;
      }
    return song;
  }

  // createPerTrackSettings() is generating a set of default settings per track
  // we may want to add some more features here in the future. For example, a proper
  // calculation of the pattern set size first - lastPattern per track is
  // useful
  function createPerTrackSettings ()
  {
    console.log ("compiling the General section...");
    var firstPattern = 1;
    var lastPattern = 31;
    var ratio = 11;
    // clock ratio (transp a)
    // [24:1, 8:1, 7:1, 6:1, 5:1, 4:1, 3:1, 2:1, 1:1, 1:2, 1:3, 1:4, 1:5, 1:6,
    // 1:7, 1:8][ratio]
    // general[0] Track Number 0-3
    // general[1] currently selected track 0/1
    // general[5] CVB Mode 0=Raw 1=Pitch
    // general[12] Clock Source 0=ext 1=int
    var general =
      "TRACK;SELECTED;RES_KIND;TIME_RES;CVA_RANGE;CVA_MODE;CVA_MUTE;GATE_A_MUTE;"
      +
      "CVB_RANGE;CVB_MODE;CVB_MUTE;GATE_B_MUTE;TR_MUTE;LOOP_LEN;ROOT;SCALE;QNTDIR;"
      +
      "GTA%;GTB%;SOURCE;SWING;LASTPAT;SONGMODE;patternmd;transp a;transp b;loop step;"
      +
      "loop pat;loop length;loop for;isLoop;trackBPM;ratio;gtFullA;gtFullB;resetWhat;"
      + "resetWhen;stageShift;gateShift a;gateShift b;chance" + crlf;
    general +=
      "0;1;0;0;0;0;0;0;0;0;50;50;0;" + firstPattern + ";" + lastPattern +
      ";0;0;0;0;0;1;1;0;" + Math.floor (tempoBPM[0]) + ";" + ratio +
      ";1;2;0;0;0;0;0;0;0;0;0;0;0;0;0;0;0;0;0;1;0;0;0;0;0;0" + crlf;
    general +=
      "1;0;0;0;0;0;0;0;0;0;50;50;0;" + firstPattern + ";" + lastPattern +
      ";0;0;0;0;0;1;1;0;" + Math.floor (tempoBPM[1]) + ";" + ratio +
      ";1;2;0;0;0;0;0;0;0;0;0;0;0;0;0;0;0;0;0;1;0;0;0;0;0;0" + crlf;
    general +=
      "2;0;0;0;0;0;0;0;0;0;50;50;0;" + firstPattern + ";" + lastPattern +
      ";0;0;0;0;0;1;1;0;" + Math.floor (tempoBPM[2]) + ";" + ratio +
      ";1;2;0;0;0;0;0;0;0;0;0;0;0;0;0;0;0;0;0;1;0;0;0;0;0;0" + crlf;
    general +=
      "3;0;0;0;0;0;0;7;0;0;50;50;0;" + firstPattern + ";" + lastPattern +
      ";0;0;0;0;0;1;1;0;" + Math.floor (tempoBPM[3]) + ";" + ratio +
      ";1;2;0;0;0;0;0;0;0;0;0;0;0;0;0;0;0;0;0;1;0;0;0;0;0;0" + crlf;
    return general;
  }

  // createGlobalSettings() is generating a set of global default settings
  // we may want to add some more features here in the future
  function createGlobalSettings ()
  {
    console.log ("compiling the Closing section...");
    var closing =
      "AllEdShPly;0Vis;aux;Master;rel temp;empty 1;empty 2;empty 3;empty 4" +
      crlf;
    closing += "3;0;0;3;0;0;0;0;0" + crlf;
    return closing;
  }

  // emptyPatterns() is used to initialize the pattern dictionaries
  function emptyPatterns ()
  {
    sinfonionDict["T3_SINF_root"] =[];
    sinfonionDict["T3_SINF_degree"] =[];
    sinfonionDict["T3_SINF_len"] =[];
    sinfonionDict["T3_SINF_gateA"] =[];
    sinfonionDict["T3_SINF_gateB"] =[];
    for (var ptype in patterns)
      patternDict[patterns[ptype]] =[];
  }

  // dumpPatterns() walks through the patternDict and concatenates all the
  // elements into the 4*5*512 value pattern line block for the project
  function dumpPatterns ()
  {
    var pcsv = "";
    for (var p in patterns)
      {
	var ptype = patterns[p];
	var parray = patternDict[ptype];
	if (checkEnableSinfonion.checked && ptype == "T3_CVA_values")
	  {
	    parray = sinfonionDict["T3_SINF_root"];
	  }
	if (checkEnableSinfonion.checked && ptype == "T3_CVB_values")
	  {
	    parray = sinfonionDict["T3_SINF_degree"];
	  }
	if (checkEnableSinfonion.checked && ptype == "T3_CVA_var_mode_len")
	  {
	    parray = sinfonionDict["T3_SINF_len"];
	  }
	if (checkEnableSinfonion.checked && ptype == "T3_GTA")
	  {
	    parray = sinfonionDict["T3_SINF_gateA"];
	  }
	if (checkEnableSinfonion.checked && ptype == "T3_GTB")
	  {
	    parray = sinfonionDict["T3_SINF_gateB"];
	  }
	for (var i = 0; i < (32 * 16); i++)
	  {
	    if (parray[i])
	      pcsv += (parray[i] + ";");
	    else
	      pcsv += ("0;");
	  }
	pcsv += (ptype + crlf);
      }
    return pcsv;
  }

  // scanDenominators() deals with note value limits
  // the usta pattern consists of 16 steps;
  // by default, we map one measure to these 16 steps which leads to a limit of
  //
  // 1/16th note values
  // we may support 1/32 note values by mapping one measure to 2*16 pattern
  // steps, this is not fully implemented yet
  function scanDenominators (cursor, measureMap)
  {
    if (!
	(cursor.element.type == Element.CHORD
	 || cursor.element.type == Element.REST))
      return;
    if (cursor.staffIdx > staffLimit)
      return;
    if (cursor.voice > voiceLimit)
      return;
    if (cursor.element.duration.denominator > 32)
      {
	errorDialog.openErrorDialog (qsTr
				     ("Note values smaller 1/32 are not supported"));
	quit;
      }
    if (cursor.element.duration.denominator > 16)
      {
	console.log (showPos (cursor, measureMap) + ": measure overrun " +
		     cursor.element.duration.nominator + "/" +
		     cursor.element.duration.denominator);
	patternsPerMeasure[cursor.staffIdx] = 2;
      }

  }

  // chord2Sinfonion translates the chord symbol into CV suitable to provide
  // the ACL Sinfonion chord sequence
  // we only use one (the first) chord for each measure
  // channel A is the root note
  // channel B is the degree of the first Chords mode
  //    turn ROOT and DEGREE full CCW to make this work properly
  // gate A fires once per measure (usable for the AB switch)
  // gate B fires each step, proving a 4 PPQ clock signal
  function chord2Sinfonion (chord, steps)
  {
    if (chord.includes ('/'))
      {
	chord = chord.slice (0, chord.lastIndexOf ("/"));
      }
    var root = chord.slice (0, 1);
    var mode = '';
    var pitch = 0;
    if (chord.slice (1, 2) == '#')
      {
	root += '#';
	mode = chord.slice (2, 9);
      }
    else if (chord.slice (1, 2) == 'b')
      {
	root += 'b';
	mode = chord.slice (2, 9);
      }
    else
      {
	mode = chord.slice (1, 9);
      }
    console.log ('root:' + root + ' mode:<' + mode + '> steps ' + steps);
    pitch = pitchValue (root);
    var degree = degreeValue (mode);
    var gateAfired = false;
    while (steps > 16)
      {
	sinfonionDict["T3_SINF_root"].push ((pitch + midiShift) * 201);
	sinfonionDict["T3_SINF_degree"].push ((degree + midiShift) * 201);
	sinfonionDict["T3_SINF_len"].push (16 * 867);
	// gate A fires once per measure
	sinfonionDict["T3_SINF_gateA"].push (4 * 867);
	// gate B fires every step (4 PPQ)
	sinfonionDict["T3_SINF_gateB"].push (16 * 867 + 289);	// 16 gates (green)
	gateAfired = true;
	steps -= 16;
      }
    sinfonionDict["T3_SINF_root"].push ((pitch + midiShift) * 201);
    sinfonionDict["T3_SINF_degree"].push ((degree + midiShift) * 201);
    sinfonionDict["T3_SINF_len"].push (steps * 867);
    if (gateAfired)
      {
	sinfonionDict["T3_SINF_gateA"].push (289 + 289);	// skip gate (red)
      }
    else
      {
	sinfonionDict["T3_SINF_gateA"].push (867);
      }
    sinfonionDict["T3_SINF_gateB"].push (steps * 867 + 289);	// # gates (green)
    return pitch + ':' + degree;
  }

  function pitchValue (root)
  {
    switch (root)
      {
      case 'C':
	return 0;
      case 'C#':
	return 1;
      case 'Db':
	return 1;
      case 'D':
	return 2;
      case 'D#':
	return 3;
      case 'Eb':
	return 3;
      case 'E':
	return 4;
      case 'F':
	return 5;
      case 'F#':
	return 6;
      case 'Gb':
	return 6;
      case 'G':
	return 7;
      case 'G#':
	return 8;
      case 'Ab':
	return 8;
      case 'A':
	return 9;
      case 'A#':
	return 10;
      case 'Bb':
	return 10;
      case 'B':
	return 11;
      default:
	return 0;
      }

  }

  function degreeValue (mode)
  {
    switch (mode)
      {
      case 'lyd':
	return 0;
      case 'maj':
      case 'Maj9':
	return 1;
      case '7':
	return 2;
      case 'sus':
      case 'sus4':
      case '7sus4':
	return 3;
      case 'alt':
	return 4;
      case 'hm5':
	return 5;
      case 'dor':
	return 6;
      case 'min':
      case 'm':
      case 'm9':
      case 'm7':		// optional min|phr
	return 7;
      case 'hm':
      case 'm(Maj7)':
	return 8;
      case 'phr':
	return 9;
      case 'dim':
	return 10;
      case 'aug':
	return 11;
      case '7(b13)':		// substitution for Chords2 Degree 5
	return 0;
      default:
	return 0;
      }
  }

  // note2CV() translates the note (and rest) elements in the score to CV and
  // gate values for the usta project
  // we may want to add some more features here in the future
  function note2CV (cursor, measureMap)
  {
    // console.log(showPos(cursor, measureMap) + ": " +
    // nameElementType(cursor.element.type));
    if (!
	(cursor.element.type == Element.CHORD
	 || cursor.element.type == Element.REST))
      return;
    if (cursor.staffIdx > staffLimit)
      return;
    if (cursor.voice > voiceLimit)
      return;

    var trackNr = cursor.staffIdx;
    var voiceNr = cursor.voice;
    if (staffMerge > 0)
      {
	trackNr =[0, 0, 1, 1, 2, 2, 3, 3][cursor.staffIdx];
	voiceNr =[0, 1, 0, 1, 0, 1, 0, 1][cursor.staffIdx];
	// alternative merge pattern
	// trackNr = [0, 1, 2, 3, 0, 1, 2, 3][cursor.staffIdx];
	// voiceNr = [0, 0, 0, 0, 1, 1, 1, 1][cursor.staffIdx];
      }

    var channel =["A", "B"][voiceNr];
    var vmod =["_var_mode_len", "_var_mode"][voiceNr];
    var vmodLen =[867, 0][voiceNr];

    var track = "T" + trackNr;
    var cvind = track + "_CV" + channel + "_values";
    var cvmod = track + "_CV" + channel + vmod;
    var gtind = track + "_GT" + channel;

    var spm = 16 * patternsPerMeasure[cursor.staffIdx];
    var beats =
      cursor.element.duration.numerator * spm /
      cursor.element.duration.denominator;
    var gridMatch = " pushing ";
    var cv = 0;
    var gate = 0;
    if (cursor.element.type == Element.CHORD)
      {
	var note = cursor.element.notes[0];
	cv = (note.pitch - midiShift) * 201;
	gate = 8 * 867;
      }
    if (cv < 0)
      {
	cv = 0;
	gate = 0;
	console.log (showPos (cursor, measureMap) +
		     ": omitting subcrontraoctave note");
      }
    if (matchGrid (cursor, measureMap))
      {
	if (checkEnableCondensed.checked)
	  {
	    while (beats > 16)
	      {
		console.log (showPos (cursor, measureMap) +
			     ": beat overrun " + beats);
		vmodLen = 867 * 16;
		patternDict[cvind].push (cv);
		patternDict[cvmod].push (vmodLen);
		patternDict[gtind].push (16 * 867);
		beats -= 16;
	      }
	    vmodLen = 867 * beats;
	    // console.log (showPos (cursor, measureMap) +
	    //           ": condensed len " + vmodLen);
	    patternDict[cvind].push (cv);
	    patternDict[cvmod].push (vmodLen);
	    patternDict[gtind].push (gate);
	  }
	else
	  {
	    gate = 16 * 867;
	    for (var b = 0; b < beats; b++)
	      {
		if (b >= (beats - 1) && cursor.element.type == Element.CHORD)
		  gate = 8 * 867;
		patternDict[cvind].push (cv);
		patternDict[cvmod].push (vmodLen);
		patternDict[gtind].push (gate);
	      }
	  }
      }
    else
      {
	gridMatch = " omitting ";
	console.log (showPos (cursor, measureMap) + ": " + cvind + "/" +
		     gtind + gridMatch + beats + " beats cv(" + cv +
		     ") gate(" + gate + ")");
      }

    // console.log(showPos(cursor, measureMap) + ": " +
    // cursor.element.duration.numerator + "/" +
    // cursor.element.duration.denominator + "::" +
    // cursor.element.globalDuration.numerator + "/" +
    // cursor.element.globalDuration.denominator );

    // console.log(showPos(cursor, measureMap) + ": " + cvind + "/" + gtind +
    // gridMatch + beats + " beats cv(" +
    // cv + ") gate(" + gate + ")" );

    return;
  }

onRun:{
    emptyPatterns ();
    var measureMap = buildMeasureMap (curScore);
    // we support more than 4 and up to 8 staves by merging two staves into
    // channels A and B of the four tracks.
    // condensed mode is disabled when merging.
    if (maxStaffId > 3)
      {
	voiceLimit = 0;
	staffLimit = 7;
	staffMerge = 1;
	checkEnableCondensed.checked = false;
      }
    // applyToSelectionOrScore(scanDenominators, measureMap);
    applyToSelectionOrScore (note2CV, measureMap);
  }

  // ******************************************************************
  //
  // GUI
  //
  // ******************************************************************

  // QT message dialog
  MessageDialog
  {
  id:errorDialog;
  visible:false;
  title:qsTr ("Error");
  text:"Error";
  onAccepted:{
      close ();
    }

    function openErrorDialog (message)
    {
      text = message;
      open ();
    }
  }

  // QT message dialog
  MessageDialog
  {
  id:endDialog;
  visible:false;
  title:qsTr ("Conversion performed");
  text:"Score has been successfully converted to USTA format." + crlf +
      "Resulting file: " + textFieldFilePath.text + "/" +
      textFieldFileName.text + crlf + crlf;
  onAccepted:{
      Qt.quit ();
    }

    function openEndDialog (message)
    {
      text = message;
      open ();
    }
  }

  // QT message dialog
  FileDialog
  {
  id:directorySelectDialog;
  title:qsTr ("Please choose a directory");
  selectFolder:true;
  visible:false;
  onAccepted:{
    var exportDirectory = this.folder.toString ().replace ("file://", "").replace (/^\/(.:\/)(.*)$ /, "$1$2");
      console.log ("Selected directory: " + exportDirectory);
      textFieldFilePath.text = exportDirectory;
      close ();
    }
  onRejected:{
      console.log ("Directory not selected");
      close ();
    }
  }

  // File names -------------------------------------------------

  Label
  {
  id:labelSpacerFilePathName;
  text:"";
  font.pixelSize:fontSize;
  width:smallWidth;
  height:bigHeight;
  horizontalAlignment:Text.AlignRight;
  verticalAlignment:Text.AlignVCenter;
  }

  Label
  {
  id:labelFilePathName;
  text:"File path and name";
  font.pixelSize:fontTitleSize;
  anchors.left:labelSpacerFilePathName.right;
  width:smallWidth;
  height:bigHeight;
  verticalAlignment:Text.AlignVCenter;
  }

  // File name

  Label
  {
  id:labelFileName;
  text:"File name  ";
  font.pixelSize:fontSize;
  anchors.top:labelSpacerFilePathName.bottom;
  width:smallWidth;
  height:stdHeight;
  horizontalAlignment:Text.AlignRight;
  verticalAlignment:Text.AlignVCenter;
  }

  TextField
  {
  id:textFieldFileName;
  placeholderText:qsTr ("file name");
  text:curScore.title.toUpperCase () + ".UST";
  anchors.top:labelSpacerFilePathName.bottom;
  anchors.left:labelFileName.right;
  width:mediumWidth;
  height:stdHeight;
  }

  Button
  {
  id:buttonFileName;
  text:"↺ Reset";
  anchors.top:labelSpacerFilePathName.bottom;
  anchors.left:textFieldFileName.right;
  width:buttonWidth;
  height:stdHeight;

    MouseArea
    {
    anchors.fill:parent;
    onClicked:textFieldFileName.text =
	curScore.title.toUpperCase () + ".UST";
    }
  }

  // Path

  Label
  {
  id:labelFilePath;
  text:"File path  ";
  font.pixelSize:fontSize;
  anchors.top:labelFileName.bottom;
  width:smallWidth;
  height:stdHeight;
  horizontalAlignment:Text.AlignRight;
  verticalAlignment:Text.AlignVCenter;
  }

  TextField
  {
  id:textFieldFilePath;
  placeholderText:qsTr ("file path");
  anchors.top:labelFileName.bottom;
  anchors.left:labelFilePath.right;
  text:dirname (curScore.path);
  width:bigWidth;
  height:stdHeight;
  enabled:false;
  }

  Button
  {
  id:buttonFilePath;
  text:"📂 Choose";
  anchors.top:labelFileName.bottom;
  anchors.left:textFieldFilePath.right;
  width:buttonWidth;
  height:stdHeight;

    MouseArea
    {
    anchors.fill:parent;
    onClicked:directorySelectDialog.open ();
    }
  }

  // Settings ----------------------------------------------------

  Label
  {
  id:labelSpacerSettings;
  text:"";
  font.pixelSize:fontSize;
  anchors.top:labelFilePath.bottom;
  width:smallWidth;
  height:bigHeight;
  horizontalAlignment:Text.AlignRight;
  verticalAlignment:Text.AlignVCenter;
  }

  Label
  {
  id:labelSettings;
  text:"Settings";
  font.pixelSize:fontTitleSize;
  anchors.top:labelFilePath.bottom;
  anchors.left:labelSpacerFilePathName.right;
  width:smallWidth;
  height:bigHeight;
  verticalAlignment:Text.AlignVCenter;
  }

  Label
  {
  id:labelEnableCondensed;
  text:"Enable condensed  ";
  font.pixelSize:fontSize;
  anchors.top:labelSpacerSettings.bottom;
  width:smallWidth;
  height:stdHeight;
  horizontalAlignment:Text.AlignRight;
  verticalAlignment:Text.AlignVCenter;
  }

  CheckBox
  {
  id:checkEnableCondensed;
  anchors.top:labelSpacerSettings.bottom;
  anchors.left:labelFilePath.right;
  checked:true;

    MouseArea
    {
    anchors.fill:parent;
    onClicked:{
	checkEnableCondensed.checked = !checkEnableCondensed.checked;
      }
    }
  }

  Label
  {
  id:labelEnableCondensedExplain;
  text:"Check to map note values to length settings (only working with up to four staves/voices).";
  font.pixelSize:fontSize;
  anchors.top:labelSpacerSettings.bottom;
  anchors.left:checkEnableCondensed.right;
  width:bigWidth;
  height:bigHeight;
  horizontalAlignment:Text.AlignLeft;
  wrapMode:Text.WordWrap;
  }

  Label
  {
  id:labelEnableSinfonion;
  text:"Enable Sinfonion ";
  font.pixelSize:fontSize;
  anchors.top:labelEnableCondensed.bottom;
  width:smallWidth;
  height:stdHeight;
  horizontalAlignment:Text.AlignRight;
  verticalAlignment:Text.AlignVCenter;
  }

  CheckBox
  {
  id:checkEnableSinfonion;
  anchors.top:labelEnableCondensed.bottom;
  anchors.left:labelFilePath.right;
  checked:true;

    MouseArea
    {
    anchors.fill:parent;
    onClicked:{
	checkEnableSinfonion.checked = !checkEnableSinfonion.checked;
      }
    }
  }

  Label
  {
  id:labelEnableSinfonionExplain;
  text:"Check to enable root and chord harmony settings for ACL Sinfonion.";
  font.pixelSize:fontSize;
  anchors.top:labelEnableCondensed.bottom;
  anchors.left:checkEnableSinfonion.right;
  width:bigWidth;
  height:stdHeight;
  horizontalAlignment:Text.AlignLeft;
  wrapMode:Text.WordWrap;
  }

  // Confirm ----------------------------------------------------

  Label
  {
  id:labelSpacerConfirm;
  text:" ";
  font.pixelSize:fontSize;
  anchors.top:labelEnableSinfonion.bottom;
  width:smallWidth;
  height:stdHeight;
  horizontalAlignment:Text.AlignRight;
  verticalAlignment:Text.AlignVCenter;
  }

  Button
  {
  id:buttonConvert;
  text:"✓ Convert";
  anchors.top:labelSpacerConfirm.bottom;
  anchors.left:labelSpacerConfirm.right;
  width:buttonWidth;
  height:stdHeight;

    MouseArea
    {
    anchors.fill:parent;
    onClicked:createCSV ();
    }
  }

  Label
  {
  id:labelInterButtons;
  text:"  ";
  font.pixelSize:fontSize;
  anchors.top:labelSpacerConfirm.bottom;
  anchors.left:buttonConvert.right;
  height:stdHeight;
  }

  Button
  {
  id:buttonClose;
  text:"✕ Close";
  anchors.top:labelSpacerConfirm.bottom;
  anchors.left:labelInterButtons.right;
  width:buttonWidth;
  height:stdHeight;

    MouseArea
    {
    anchors.fill:parent;
    onClicked:Qt.quit ();
    }
  }
}
