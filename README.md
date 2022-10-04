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

## What next?

Using the plugin is pretty self-explanatory.
When you start it, a dialog box appears in which you can specify the name and location for the Usta project file.
What is not immediately clear can surely be clarified with a few tries by yourself.

There are certainly real bugs or flaws for certain use cases.
To document this or to give suggestions, an issue should be filed here in GitHub.
For fixes or enhancements and to share more examples, feel free to make a pull request.

There is nothing more to say.
Have fun making noise.
