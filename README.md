# MuseScore plugin to export scores in Usta project format.

The folks at FrapTools call their sequencer "The CV Score."
How apt this analogy is becomes clear when you look at a UST project file or load it into a spreadsheet.
Each new project is like a blank sheet of music with 8 lines and 32 measures for 16th notes each. It wants to be filled.

This plugin allows you to export a MuseScore score with these dimensions in Usta project format.

The resulting file must then be copied to the module's SD card.
The file name has to follow the 8.3 convention and has to be specified in capital letters in order to be recognized by Usta.
The plugin uses the workTitle property as default name for the project file.

## What is this Usta thing?

It is a synthesizer module in EuroRack format.
It generates sequences of control voltages (CV) and gates with which other modules can be controlled.

There is more information about modular synthesizers in general and the Usta Sequencer on the internet.

This plugin is unfortunately only for people who happen to own such a Usta Sequencer.
But for them the plugin is hopefully of great use.

## What is this plugin used for?

As I said, the space in a score spanned by the Usta project is quite large.
Screwing all CV and gate values into the sequencer by hand via the encoders is possible, but for a creative workflow this is boring in the long run.
The plugin makes it possible to do the creation of a score in a tool optimized for this purpose.
The open-source program MuseScore is just such a tool, and its plugin architecture allows exactly this sensible division of the creative workflow.
The score is created in MuseScore, and after exporting it, the project can then be further developed and adjusted while playing in the seqencer.
At the same time, MuseScore is so powerful and flexible that it can read scores from other sources and in many formats, making them usable for export as a Usta project.

In the simplest case, it is possible to load any existing score into MuseScore and export it.
The plugin punches the first 32 bars of the first 8 staves out of the score, so to speak.
Only the first voice of each staff and one note of each chord is exported.
If there are only up to four staves in the score, a second voice is recognized.
Both voices are then exported as channel A and B in the respective tracks.
Note values smaller than 16th notes are simply ignored.
Pitches lower than C0 (MIDI 24) are ignored.

However, these restrictions are not a hindrance to the creative process.
After all, the goal is not to reproduce existing polyphonic compositions for orchestra exactly on the synthesizer.
Errors in the mapping process lead to surprising and interesting effects in the sound result.

Starting from arbitrary scores as raw material, the tool invites creative reshaping.
Chords can be distributed over several staves.
Phrases and whole passages can be recombined as a collage.
And, of course, entire scores can be composed especially for the sequencer.
Pitch can also be interpreted as control voltage for any other purpose.

## Condensed Mode

In order to realize the maximum number of 8 independent note lines, each with independent note values for channels A and B, the note values are realized during export by concatenating the corresponding number of equal 1/16th (4PPQ) length stages. In Condensed Mode, with a maximum of 4 note lines, the note values in the Usta are mapped to the stage length.

In normal export, typically one bar at a time is written to a 16-stage pattern. This way all tracks simply stay in time, but only 32 measures fit on the CV score.

In Condensed Mode, a new note is written for each stage of a pattern. This way the bar boundaries often do not fall itno the patterns of the tracks. Because the parallel staves typically do not contain exactly the same number of notes, the patterns are also often of different lengths.

If all the tracks start synchronously, the whole piece will be in time until the first track reaches the end and starts again with the first pattern. From then on, the tracks shift more and more against each other. As in a canon or a fugue, these shifts can provide interesting new sonic experiences.

## Sinfonion Mode

If Usta is the CV score, the ACL Sinfonion is the CV conductor. The Sinfonion provides harmony in up to 8 parallel voices.

To deepen the possibility of multi-layered collages already hinted at in Condensed Mode and to provide them with a harmonic framework, the fourth track of the Usta is used in Sinfonion Mode to control the Chord Sequencer in the Sinfonion.

A chord symbol is evaluated for each bar in the score. The root note is stored in channel A. In channel B, the degree is used to select the scale for the chord in the Sinfonion. Only the first chords mode is supported at the moment.

In gate A of track 4 a trigger is sent at the beginning of each new bar.
In gate B of track 4 a 4 PPQ clock signal is output for synchronization with other modules.

## Skip Measures

When exporting existing scores and / or for creating interesting collages, it is sometimes helpful to exclude parts of the score from the export. For this purpose it is now possible to simply attach a staff text to the first bar of the corresponding section, specifying the staves and the number of bars to skip. For example, a comment `usta skip 2:6,4:9` skips 6 bars of note line two and 9 bars of note line 4, each starting from the bar in which the note is attached. The counting of the staves starts at 1.

## Sync Measures

When exporting multiple staves in condensed mode, the synchronization of bars within the pattern is usually lost. The bars of the different staves start in different stages in the middle of the pattern.

In order to create the possibility here of starting the staves synchronously at certain bars, a staff text can simply be appended to the corresponding bar, in which the staves to be synchronized are specified. For example, the comment `usta sync 1,3` ensures that the first notes of lines one and three are mapped to the first stage of a pattern. If there are still free stages in a pattern, a corresponding number of empty stages will be inserted.


## What next?

Using the plugin is pretty self-explanatory.
When you start it, a dialog box appears in which you can specify the name and location for the Usta project file.
What is not immediately clear can surely be clarified with a few tries by yourself.

There are certainly real bugs or flaws for certain use cases.
To document this or to give suggestions, an issue should be filed here in GitHub.
For fixes or enhancements and to share more examples, feel free to make a pull request.

There is nothing more to say.
Have fun making noise.
