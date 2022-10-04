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

import QtQuick 2.9
import QtQuick.Controls 1.4
import QtQuick.Layouts 1.3
import QtQuick.Dialogs 1.2
import Qt.labs.settings 1.0
// FileDialog
import Qt.labs.folderlistmodel 2.2
import QtQml 2.8
import MuseScore 3.0
import FileIO 3.0

MuseScore {
	description: "Export to FrapTools Usta Sequencer"
	menuPath: "Plugins." + "Frap Usta Export"
	version: "1.0"
	requiresScore: true;
	pluginType: "dialog"
	id: window
	width: 800
	height: 200

	property int buttonWidth: 80
	property int smallWidth: 150
	property int mediumWidth: 300
	property int bigWidth: 500
	property int stdHeight: 24
	property int bigHeight: 45
	property int fontTitleSize: 16
	property int fontSize: 12
	property string crlf: "\r\n"
	property var patternDict: []
	property var patterns: ["T0_CVA_values", "T0_CVB_values", "T0_CVA_var_mode_len", "T0_CVB_var_mode",
	"T0_GTA", "T0_GTB", "T1_CVA_values", "T1_CVB_values", "T1_CVA_var_mode_len", "T1_CVB_var_mode",
	"T1_GTA", "T1_GTB", "T2_CVA_values", "T2_CVB_values", "T2_CVA_var_mode_len", "T2_CVB_var_mode",
	"T2_GTA", "T2_GTB", "T3_CVA_values", "T3_CVB_values", "T3_CVA_var_mode_len", "T3_CVB_var_mode",
	"T3_GTA", "T3_GTB"]
	property var patternsPerMeasure: [1, 1, 1, 1, 1, 1, 1, 1]
	property var maxVoiceId: 0
	property var voiceLimit: 1
	property var maxStaffId: 0
	property var staffLimit: 3
	property var staffMerge: 0
	// MIDI note 0 is C-2@8.176Hz
	// Usta has a pitch range starting with 0V named either C0 or A0, negative CV values are not supported for pitch
	// to match the MuseScore note values with the Usta range, we ignore the two lowest octaves and shift the MIDI note values 24 semitones down.
	property var midiShift: 24

	// buildMeasureMap() calculates the metrics of the score into the map dict structure
	// to provide some context in further passes through the score
	function buildMeasureMap(score) {
		var map = {};
		var no = 1;
		var cursor = score.newCursor();
		cursor.rewind(Cursor.SCORE_START);
		while (cursor.measure) {
			var m = cursor.measure;
			var tick = m.firstSegment.tick;
			var tsD = m.timesigActual.denominator;
			var tsN = m.timesigActual.numerator;
			var ticksB = division * 4.0 / tsD;
			var ticksM = ticksB * tsN;
			no += m.noOffset;
			var cur = {
				"tick": tick,
				"tsD": tsD,
				"tsN": tsN,
				"ticksB": ticksB,
				"ticksM": ticksM,
				"past" : (tick + ticksM),
				"no": no
			};
			map[cur.tick] = cur;
			// console.log(tsN + "/" + tsD + " measure " + no + " at tick " + cur.tick + " length " + ticksM);
			if (!m.irregular)
				++no;
	    if (cursor.staffIdx > maxStaffId)
				maxStaffId = cursor.staffIdx;
			if (cursor.voice > maxVoiceId)
				maxVoiceId = cursor.voice;
			cursor.nextMeasure();
		}
		return map;
	}

	// applyToSelectionOrScore(cb, ...args) is the workhorse which walks
	// through the current score or selection thereof element by element and applies a
  // callback function with possible args
	function applyToSelectionOrScore(cb) {
		var args = Array.prototype.slice.call(arguments, 1);
		var staveBeg;
		var staveEnd;
		var tickEnd;
		var rewindMode;
		var toEOF;

		var cursor = curScore.newCursor();
		cursor.rewind(Cursor.SELECTION_START);
		if (cursor.segment) {
			staveBeg = cursor.staffIdx;
			cursor.rewind(Cursor.SELECTION_END);
			staveEnd = cursor.staffIdx;
			if (!cursor.tick) {
				/*
				 * This happens when the selection goes to the
				 * end of the score — rewind() jumps behind the
				 * last segment, setting tick = 0.
				 */
				toEOF = true;
			} else {
				toEOF = false;
				tickEnd = cursor.tick;
			}
			rewindMode = Cursor.SELECTION_START;
		} else {
			/* no selection */
			staveBeg = 0;
			staveEnd = curScore.nstaves - 1;
			toEOF = true;
			rewindMode = Cursor.SCORE_START;
		}

		for (var stave = staveBeg; stave <= staveEnd; ++stave) {
			for (var voice = 0; voice < 4; ++voice) {
				cursor.staffIdx = stave;
				cursor.voice = voice;
				cursor.rewind(rewindMode);
				/*XXX https://musescore.org/en/node/301846 */
				cursor.staffIdx = stave;
				cursor.voice = voice;

				while (cursor.segment &&
				    (toEOF || cursor.tick < tickEnd)) {
					if (cursor.element)
						cb.apply(null,
						    [cursor].concat(args));
					cursor.next();
				}
			}
		}
	}

	// showPos is a debugging function which makes use of the measureMap metrics to
	// position the current event inside the staff/voice/measure space
	function showPos(cursor, measureMap) {
		var t = cursor.segment.tick;
		var m = measureMap[cursor.measure.firstSegment.tick];
		var b = "?";
		if (m && t >= m.tick && t < m.past) {
			b = 1 + (t - m.tick) / m.ticksB;
		}

		return "St" + (cursor.staffIdx + 1) +
		    " Vc" + (cursor.voice + 1) +
		    " Ms" + m.no + " Bt" + b;
	}

  // matchGrid checks if the cursor is matching a 16th note grid pattern
	function matchGrid(cursor, measureMap) {
		var t = cursor.segment.tick;
		var m = measureMap[cursor.measure.firstSegment.tick];
		var b = 0;
		if (m && t >= m.tick && t < m.past) {
			b = ((t - m.tick) / m.ticksB) % 0.25;
		}
		if (b > 0) {
			return 0;
		}
		return 1;
	}

	// nameElementType() knows about all the possible elements that can appear inside
	// a score. Currently, we only care about CHORD and REST, but this may change in
	// the future.
	function nameElementType(elementType) {
		switch (elementType) {
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
	function dirname(p) {
        	return (p.slice(0,p.lastIndexOf("/")+1))
    	}

	// QT message dialog
	MessageDialog {
		id: errorDialog
		visible: false
		title: qsTr("Error")
		text: "Error"
		onAccepted: {
			close()
		}

		function openErrorDialog(message) {
			text = message
			open()
		}
	}

	// QT message dialog
	MessageDialog {
		id: endDialog
		visible: false
		title: qsTr("Conversion performed")
		text: "Score has been successfully converted to USTA format." + crlf + "Resulting file: " + textFieldFilePath.text + "/" + textFieldFileName.text + crlf + crlf
		onAccepted: {
			Qt.quit()
		}

		function openEndDialog(message) {
			text = message
			open()
		}
	}

	// QT message dialog
	FileDialog {
		id: directorySelectDialog
		title: qsTr("Please choose a directory")
		selectFolder: true
		visible: false
		onAccepted: {
			var exportDirectory = this.folder.toString().replace("file://", "").replace(/^\/(.:\/)(.*)$/, "$1$2")
			console.log("Selected directory: " + exportDirectory)
			textFieldFilePath.text = exportDirectory
			close()
		}
		onRejected: {
			console.log("Directory not selected")
			close()
		}
	}

	// FileIO is the QT object which handles all the heavy lifting
	FileIO {
		id: csvWriter
		onError: console.log(msg + "  Filename = " + csvWriter.source)
	}

	// createCSV() is the actual export method in which the usta sequencer project
	// data is compiled and written into a file.
	// The project consists of four parts; the songs part, a per track settings part,
	// 4*5 lines of patterns and a closing part with global settings.
	function createCSV() {

		if (!textFieldFileName.text) {
			errorDialog.openErrorDialog(qsTr("File name not specified"))
			return
		} else if (!textFieldFilePath.text) {
			errorDialog.openErrorDialog(qsTr("File folder not specified"))
			return
		}
		if (textFieldFileName.text == ".UST")
			textFieldFileName.text = "SCORE.UST"
		var csv = ""

		csv += createSongs()
		csv += createPerTrackSettings()
		csv += dumpPatterns()
		csv += createGlobalSettings()
		var filename = textFieldFilePath.text + "/" + textFieldFileName.text
		console.log("export to " + filename)
		csvWriter.source = filename
		console.log("writing csv...")
		csvWriter.write(csv)
		console.log("conversion performed")
		endDialog.open()
	}

	// createSongs() is generating four lines of default (empty) song structures
	// we may want to add some more features here in the future
	// a random song generator may be interesting
	function createSongs() {
		console.log("compiling the Song section...")
		var song = ""
		for (var s = 0; s < 4; s++) {
		    for (var i = 0; i < 130; i++) {
			if (i == 65)
				song += "1;"
			else
				song += "0;"
		    }
		    song += "SONG " + s + crlf
		}
		return song
	}

	// createPerTrackSettings() is generating a set of default settings per track
	// we may want to add some more features here in the future
	// a proper calculation of the pattern set size is useful
	function createPerTrackSettings() {
		console.log("compiling the General section...")
		var general = "TRACK;SELECTED;RES_KIND;TIME_RES;CVA_RANGE;CVA_MODE;CVA_MUTE;GATE_A_MUTE;CVB_RANGE;CVB_MODE;CVB_MUTE;GATE_B_MUTE;TR_MUTE;LOOP_LEN;ROOT;SCALE;QNTDIR;GTA%;GTB%;SOURCE;SWING;LASTPAT;SONGMODE;patternmd;transp a;transp b;loop step;loop pat;loop length;loop for;isLoop;trackBPM;ratio;gtFullA;gtFullB;resetWhat;resetWhen;stageShift;gateShift a;gateShift b;chance" + crlf
		general += "0;1;0;0;0;1;0;0;0;0;50;50;1;0;0;0;0;0;0;0;1;1;0;96;1;1;2;0;0;0;0;0;0;0;0;0;0;0;0;0;0;0;0;0;1;0;0;0;0;0;0" + crlf
		general += "1;0;0;0;0;1;0;0;0;0;50;50;1;0;31;0;0;0;0;0;1;1;0;96;5;1;2;0;0;0;0;0;0;0;0;0;0;0;0;0;0;0;0;0;1;0;0;0;0;0;0" + crlf
		general += "2;0;0;0;0;1;0;0;0;0;50;50;1;0;31;0;0;0;0;0;1;1;0;96;7;1;2;0;0;0;0;0;0;0;0;0;0;0;0;0;0;0;0;0;1;0;0;0;0;0;0" + crlf
		general += "3;0;0;0;0;1;0;7;0;0;50;50;1;0;0;0;0;0;0;0;1;1;0;120;7;1;2;0;0;0;0;0;0;0;0;0;0;0;0;0;0;0;0;0;1;0;0;0;0;0;0" + crlf
		return general
	}

	// createGlobalSettings() is generating a set of global default settings
	// we may want to add some more features here in the future
	function createGlobalSettings() {
		console.log("compiling the Closing section...")
		var closing = "AllEdShPly;0Vis;aux;Master;rel temp;empty 1;empty 2;empty 3;empty 4" + crlf
		closing += "1;0;0;1;0;0;0;0;0" + crlf
		return closing
	}

	// emptyPatterns() is used to initialize ze patternDict
	function emptyPatterns() {
		for (var ptype in patterns)
			patternDict[patterns[ptype]] = []
	}

	// dumpPatterns() walks through the patternDict and concatenates all the elements into
	// the 4*5*512 value pattern line block for the project
	function dumpPatterns() {
		var pcsv = ""
		for (var p in patterns) {
			var ptype = patterns[p]
			var parray = patternDict[ptype]
			for (var i = 0; i < (32*16); i++) {
				if (patternDict[ptype][i])
					pcsv += ( patternDict[ptype][i] + ";" )
				else
					pcsv += ( "0;" )
			}
			pcsv += ( ptype + crlf )
		}
		return pcsv
	}

	// scanDenominators() deals with note value limits
	// the usta pattern consists of 16 steps;
	// by default, we map one measure to these 16 steps which leads to a limit of 1/16th note values
	// we may support 1/32 note values by mapping one measure to 2*16 pattern steps
	// this is not fully implemented yet
	function scanDenominators(cursor, measureMap) {
		if (!(cursor.element.type == Element.CHORD || cursor.element.type == Element.REST))
			return;
		if (cursor.staffIdx > staffLimit)
			return;
		if (cursor.voice > voiceLimit)
			return;
		if ( cursor.element.duration.denominator > 32 ) {
			errorDialog.openErrorDialog(qsTr("Note values smaller 1/32 are not supported"))
			quit;
		}
		if ( cursor.element.duration.denominator > 16 ) {
			console.log(showPos(cursor, measureMap) + ": measure overrun " +
		    	cursor.element.duration.nominator + "/" + cursor.element.duration.denominator );
			patternsPerMeasure[cursor.staffIdx] = 2
		}

	}

	// note2CV() translates the note (and rest) elements in the score to CV and gate values
	// for the usta project
	// we may want to add some more features here in the future
	function note2CV(cursor, measureMap) {
		//console.log(showPos(cursor, measureMap) + ": " +
		//    nameElementType(cursor.element.type));
		if (!(cursor.element.type == Element.CHORD || cursor.element.type == Element.REST))
			return;
		if (cursor.staffIdx > staffLimit)
			return;
		if (cursor.voice > voiceLimit)
			return;

		var trackNr = cursor.staffIdx
		var voiceNr = cursor.voice
		if (staffMerge > 0) {
			trackNr = [0, 0, 1, 1, 2, 2, 3, 3][cursor.staffIdx]
			voiceNr = [0, 1, 0, 1, 0, 1, 0, 1][cursor.staffIdx]
			// alternative merge pattern
			// trackNr = [0, 1, 2, 3, 0, 1, 2, 3][cursor.staffIdx]
			// voiceNr = [0, 0, 0, 0, 1, 1, 1, 1][cursor.staffIdx]
		}

		var channel = ["A", "B"][voiceNr]
		var vmod = ["_var_mode_len", "_var_mode"][voiceNr]
		var vmodLen = [867, 0][voiceNr]

		var track = "T" + trackNr
		var cvind = track + "_CV" + channel + "_values"
		var cvmod = track + "_CV" + channel + vmod
		var gtind = track + "_GT" + channel

		var spm = 16 * patternsPerMeasure[cursor.staffIdx]
		var beats = cursor.element.duration.numerator * spm / cursor.element.duration.denominator
    var gridMatch = " pushing "
		var cv = 0
		var gate = 0
		if (cursor.element.type == Element.CHORD) {
			var note = cursor.element.notes[0]
			cv = (note.pitch - midiShift) * 201
			gate = 16 * 867
		}
		if (matchGrid(cursor, measureMap)) {
			for (var b = 0; b < beats; b++) {
				if ( b >= (beats - 1) && cursor.element.type == Element.CHORD )
					gate = 8 * 867
				if (cv < 0) {
				  cv = 0
					gate = 0
					console.log(showPos(cursor, measureMap) + ": omitting subcrontraoctave note")
				}
				patternDict[cvind].push(cv)
				patternDict[cvmod].push(vmodLen)
				patternDict[gtind].push(gate)
			}
		}	else {
			gridMatch = " omitting "
			console.log(showPos(cursor, measureMap) + ": " + cvind + "/" + gtind + gridMatch + beats + " beats cv(" +
			  cv + ") gate(" + gate + ")" );
		}

		//console.log(showPos(cursor, measureMap) + ": " +
		//    cursor.element.duration.numerator + "/" + cursor.element.duration.denominator + "::" + cursor.element.globalDuration.numerator + "/" + cursor.element.globalDuration.denominator );

		//console.log(showPos(cursor, measureMap) + ": " + cvind + "/" + gtind + gridMatch + beats + " beats cv(" +
		//  cv + ") gate(" + gate + ")" );

		return;
	}

	onRun: {
		var measureMap = buildMeasureMap(curScore);
		emptyPatterns()
		if (maxStaffId > 3){
		  voiceLimit = 0
			staffLimit = 7
			staffMerge = 1
		}
		// applyToSelectionOrScore(scanDenominators, measureMap);
		applyToSelectionOrScore(note2CV, measureMap);
	}

	// ******************************************************************
	//
	// GUI
	//
	// ******************************************************************


	// File names -------------------------------------------------

	Label {
		id: labelSpacerFilePathName
		text: ""
		font.pixelSize: fontSize
		width: smallWidth
		height: bigHeight
		horizontalAlignment: Text.AlignRight
		verticalAlignment: Text.AlignVCenter
	}

	Label {
		id: labelFilePathName
		text: "File path and name"
		font.pixelSize: fontTitleSize
		anchors.left: labelSpacerFilePathName.right
		width: smallWidth
		height: bigHeight
		verticalAlignment: Text.AlignVCenter
	}

	// File name

	Label {
		id: labelFileName
		text: "File name  "
		font.pixelSize: fontSize
		anchors.top: labelSpacerFilePathName.bottom;
		width: smallWidth
		height: stdHeight
		horizontalAlignment: Text.AlignRight
		verticalAlignment: Text.AlignVCenter
	}

	TextField {
		id: textFieldFileName
		placeholderText: qsTr("file name")
		text: curScore.title.toUpperCase() + ".UST"
		anchors.top: labelSpacerFilePathName.bottom;
		anchors.left: labelFileName.right;
		width: mediumWidth
		height: stdHeight
	}

	Button {
		id: buttonFileName
		text: "↺ Reset"
		anchors.top: labelSpacerFilePathName.bottom;
		anchors.left: textFieldFileName.right;
		width: buttonWidth
		height: stdHeight

		MouseArea {
			anchors.fill: parent
			onClicked: textFieldFileName.text = curScore.title.toUpperCase() + ".UST"
		}
	}

	// Path

	Label {
		id: labelFilePath
		text: "File path  "
		font.pixelSize: fontSize
		anchors.top: labelFileName.bottom;
		width: smallWidth
		height: stdHeight
		horizontalAlignment: Text.AlignRight
		verticalAlignment: Text.AlignVCenter
	}

	TextField {
		id: textFieldFilePath
		placeholderText: qsTr("file path")
		anchors.top: labelFileName.bottom
		anchors.left: labelFilePath.right
    text: dirname(curScore.path)
		width: bigWidth
		height: stdHeight
		enabled: false
	}

	Button {
		id: buttonFilePath
		text: "📂 Choose"
		anchors.top: labelFileName.bottom;
		anchors.left: textFieldFilePath.right;
		width: buttonWidth
		height: stdHeight

		MouseArea {
			anchors.fill: parent
			onClicked: directorySelectDialog.open()
		}
	}


	// Confirm ----------------------------------------------------

	Label {
		id: labelSpacerConfirm1
		text: " "
		font.pixelSize: fontSize
		anchors.top: labelFilePath.bottom;
		width: smallWidth
		height: bigHeight
		horizontalAlignment: Text.AlignRight
		verticalAlignment: Text.AlignVCenter
	}

	Button {
		id: buttonConvert
		text: "✓ Convert"
		anchors.top: labelSpacerConfirm1.bottom;
		anchors.left: labelSpacerConfirm1.right;
		width: buttonWidth
		height: stdHeight

		MouseArea {
			anchors.fill: parent
			onClicked: createCSV()
		}
	}

	Label {
		id: labelInterButtons
		text: "  "
		font.pixelSize: fontSize
		anchors.top: labelSpacerConfirm1.bottom;
		anchors.left: buttonConvert.right;
		height: stdHeight
	}

	Button {
		id: buttonClose
		text: "✕ Close"
		anchors.top: labelSpacerConfirm1.bottom;
		anchors.left: labelInterButtons.right;
		width: buttonWidth
		height: stdHeight

		MouseArea {
			anchors.fill: parent
			onClicked: Qt.quit()
		}
	}
}