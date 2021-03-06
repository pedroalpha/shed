//Convert SRT time format to integer milliseconds
int srt2ms(string srt)
{
	sscanf(srt,"%d:%d:%d,%d",int hr,int min,int sec,int ms);
	return hr*3600000+min*60000+sec*1000+ms;
}

//Clean up any encoding messes. Currently decodes UTF-8 and CRLF; can be
//extended to tidy up anything else within reason (eg using another charset
//if the data isn't UTF-8).
string decode(string data)
{
	return utf8_to_string(data) - "\r" - "\uFEFF";
}

//Trim junk off a line - markers of various sorts that we don't care about
//Note that this will be called on the synchronization line, and MUST NOT damage it
string trim(string line)
{
	line = replace(line, ({"<i>", "</i>"}), "");
	if (has_prefix(line, "#")) line = line[1..];
	if (has_prefix(line, "-")) line = line[1..];
	return String.trim_all_whites(line);
}

int main(int argc,array(string) argv)
{
	mapping args = Arg.parse(argv);
	[string outfn, array(string) files] = Array.pop(args[Arg.REST]);
	if (sizeof(files)<2) exit(0, #"USAGE: pike %s input1.srt input2.srt [input3.srt...] output.srt
Attempts to 'zip' the inputs into the output. Options:
	--oneline - fold each block to a single line
	--translit=language - add a transliteration back to Latin
	--trim - trim off leading/trailing '#', '-', '<i>', etc
");
	write("Combining to %s:\n%{\t%s\n%}",outfn,files);
	function translit;
	if (args->translit)
	{
		translit=((object)"translit.pike")[String.capitalize(args->translit) + "_to_Latin"];
		if (!translit) write("WARNING: %O transliteration not found, ignoring\n", args->translit);
	}
	//The first file is the one that creates the final output. All other
	//files are simply merged into the nearest slot based on start time.
	//Also: That is one serious line of code. I'm not sure this is *good* code, but it's impressive how much automap will do for you.
	[array(array(string)) output,array(array(array(string))) inputs]=Array.shift((String.trim_all_whites(decode(Stdio.read_file(files[*])[*])[*])[*]/"\n\n")[*][*]/"\n");
	//Trim off any index markers. We can re-add them later if they're wanted.
	foreach (output; int i; array(string) lines)
	{
		lines -= ({""});
		if (lines[0] == (string)(int)lines[0]) lines = lines[1..];
		if (args->trim) foreach (lines; int j; string line) lines[j] = trim(line);
		if (args->oneline) lines = ({lines[0], lines[1..] * " ", ""}) + ({""}) * !!translit;
		output[i] = lines;
	}
	foreach (inputs,array(array(string)) input)
	{
		int pos=0; //We'll never put anything earlier in the file than a previous insertion. (Also speeds up the search; in the common cases, we'll check just two or three entries.)
		foreach (input,array(string) lines)
		{
			if (lines[0]==(string)(int)lines[0]) lines=lines[1..]; //As above, trim off index markers; it's more important here as they're likely to be flat-out wrong after the merge.
			int inputtime=srt2ms(lines[0]);
			while (pos<sizeof(output)-1)
			{
				//See if pos should be incremented.
				//The current rule is: If the next output starts before, or no more than one second after, the current input, advance.
				//This allows a little slop in the alignment, but defaults to connecting pieces together.
				//Note that once we reach the end of the template file, everything will just be appended to the last entry.
				int nextouttime=srt2ms(output[pos+1][0]);
				if (nextouttime-1000<inputtime) ++pos; else break;
			}
			if (args->trim) foreach (lines; int j; string line) lines[j] = trim(line);
			if (args->oneline)
			{
				string text = lines[1..] * " ";
				if (output[pos][2] != "") text = " " + text;
				output[pos][2] += text;
				if (translit) output[pos][3] += translit(text);
			}
			else
			{
				if (translit) output[pos] += ({translit(lines[1])});
				output[pos] += lines[1..];
			}
		}
	}
	Stdio.write_file(outfn,string_to_utf8(String.trim_all_whites((output[*]*"\n")[*])*"\n\n"+"\n"));
}
