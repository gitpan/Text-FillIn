package Text::FillIn;
use Carp;
use FileHandle;
use strict;
use vars ('$LEFT_DELIM', '$RIGHT_DELIM', '%HOOK', '@TEMPLATE_PATH');
$Text::FillIn::VERSION = '0.01';


$LEFT_DELIM  ||= '[[';
$RIGHT_DELIM ||= ']]';

$HOOK{'$'} ||= \&find_value;
$HOOK{'&'} ||= \&run_function;

@TEMPLATE_PATH = ('.') unless defined @TEMPLATE_PATH;

sub new {
	my $package = shift;
	my $text = shift;
		
	my $self = {
		'text' => $text,
		'properties' => {},
	};
	
	return bless ($self, $package);
}

sub get_file {
	my $self = shift;
	my $file = shift;
	my ($realfile, $dir, @file, $fh);
	
	if ($file eq 'null') {
		$self->{'text'} = '';
		return;
	}
	
	# Find out what file to open:
	if ($file =~ /^\//) {
		$realfile = $file;
	} else {
		foreach $dir (@TEMPLATE_PATH) {
			if ( -f "$dir/$file" ) {
				$realfile = "$dir/$file";
				last;
			}
		}
	}

	unless ($realfile  and  -f $realfile) {
		warn ("Can't find file '$file' in @TEMPLATE_PATH");
		return 0;
	}

	
	unless ( defined ($fh = new FileHandle($realfile)) ) {
		warn ("Can't open $realfile: $!");
		$self->{'text'} = '';
		return 0;
	}
	
	$self->{'text'} = join('', $fh->getlines );
	return 1;
}

sub set_text {
	my $self = shift;
	my $text = shift;
	
	$self->{'text'} = $text;
}

sub get_text {
	my $self = shift;
	
	return $self->{'text'};
}

sub interpret {
	my $self = shift;
	return &_interpret_engine($self->{'text'}, 'collect');
}

sub interpret_and_print {
	my $self = shift;
	
	return &_interpret_engine($self->{'text'}, 'print');
}

sub get_property {
	my $self = shift;
	my $prop_name = shift;
	
	return $self->{'properties'}->{$prop_name};
}

sub set_property {
	my $self = shift;
	my $prop_name = shift;
	my $prop_val = shift;
	
	$self->{'properties'}->{$prop_name} = $prop_val;
}



############################# Private functions

sub _deal_with {
	my ($text, $style, $outref) = @_;
	if ($style eq 'print') {
		print $text;
	} elsif ($style eq 'collect') {
		${$outref} .= $text;
	}
}

sub _interpret_engine {

	my $text = shift;
	my $style = shift;
	my ($first_right, $first_left, $last_left, $out_text, $save);
	my $debug = 0;
	my $debug2 = 0;
	
	my $LEFT_DELIM_RX  = quotemeta($LEFT_DELIM);
	my $RIGHT_DELIM_RX  = quotemeta($RIGHT_DELIM);

	while (1) {

		print STDERR ("interpreting '$text'\n") if $debug;
		# Shave off any leading plain text before the first real [[
		my ($prelength, $pretext);
		$first_left = &_real_index($text, $LEFT_DELIM_RX);
		print STDERR ("first left is at $first_left\n") if $debug;
		if ( $first_left == -1 ) {
			# No more to do, just spit out the text
			&_unquote(\$text);
			&_deal_with($text, $style, \$out_text);
			last;
			
		} elsif ($first_left > 0) { # There's a real [[ here
			$pretext = substr($text, 0, $first_left);
			&_unquote(\$pretext);
			&_deal_with($pretext, $style, \$out_text);
			substr($text, 0, $first_left) = '';
			next;
		}
		
		# Find the first right delimiter and fill in before it:
		$first_right = &_real_index($text, $RIGHT_DELIM_RX);
		print STDERR ("first right is at $first_right\n") if $debug;
		$last_left = &_real_index(substr($text, 0, $first_right), $LEFT_DELIM_RX, 1);
		print STDERR ("last left is at $last_left\n") if $debug;
		
		if ($first_right == -1) { # Something's amiss, abort
			warn ("Problem interpreting text " . substr($text, 0, $first_right));
			&_deal_with($text, $style, \$out_text);
			last;
		}
		# Fill in the text in between the first right delimiter and the last left delimiter before it:
		substr($text, $last_left, $first_right - $last_left + 2) =
		   &_do_interpret(substr($text, $last_left, $first_right - $last_left + 2));
	}
	return $out_text;
}

sub _real_index {
	# Finds the first occurrence of $exp in $text before 
	# position $before that doesn't follow a backslash
	
	my $text = shift;
	my $exp = shift;
	my $last = shift;
	
	if ($last) {
		if ($text =~ / (.*)(^|[^\\])$exp /xs) {
			return(length($1) + length($2));
		} else {
			return -1;
		}
	} else {
		if ($text =~ /(.*?)(^|[^\\])$exp/s) {
			return (length($1) + length($2)); #`
		} else {
			return -1;
		}
	}
}

sub _unquote {
	my $textref = shift;
	
	my $RIGHT_DELIM_RX = quotemeta($RIGHT_DELIM);
	my $LEFT_DELIM_RX  = quotemeta($LEFT_DELIM);
	
	${$textref} =~ s/ \\($RIGHT_DELIM_RX|$LEFT_DELIM_RX) /$1/xgs;
}

sub _do_interpret {
	my $string = shift;
	
	my $RIGHT_DELIM_RX = quotemeta($RIGHT_DELIM);
	my $LEFT_DELIM_RX  = quotemeta($LEFT_DELIM);
	
	unless ($string =~ /^ $LEFT_DELIM_RX \s*  ([\W])  (.*?) \s*  $RIGHT_DELIM_RX $/sx ) {
		# Looks like we weren't meant to see this - but we can't interpret it again either
		carp ("Can't interpret template chunk '$string'");
		return '';
	}
	
	no strict('refs');  # Allow symbolic name substitution for a little while
	
	if ($HOOK{$1}) {
		return &{$HOOK{$1}}($2);
	} else {
		croak ("No interpret hook defined for type '$1'");
	}
}


############################ Sample hook functions ##########################


sub find_value { $main::TVars{ $_[0] } }

sub run_function {
   # Usage: $result = &run_function("some_function(param1,param2,param3)");
   my ($function_name, $args) = $_[0] =~ /(\w+)\((.*)\)/
      or die ("Can't understand function call '$_[0]'");
	no strict('refs');  # Allow symbolic name substitution for a little while
   return &{"TExport::$function_name"}( split(/,/, $args) );
}


1;

__END__


=head1 NAME

Text::FillIn.pm - a class implementing a fill-in template

=head1 SYNOPSIS

 use Text::FillIn;

 $Text::FillIn::HOOK{'$'} = sub { return ${$_[0]} };  # Hard reference
 $Text::FillIn::HOOK{'&'} = "main::run_function";     # Symbolic reference
 sub run_function { return &{$_[0]} }

 $template = new Text::FillIn('some text with [[$variables]] and [[&routines]]');
 $filled_in = $template->interpret();  # Returns filled-in template
 print $filled_in;
 $template->interpret_and_print();  # Prints template to currently selected filehandle

 # Or
 $template = new Text::FillIn();
 $template->set_text('the text is [[ $[[$var1]][[$var2]] ]]');
 $TVars{'var1'} = 'two_';
 $TVars{'var2'} = 'parter';
 $TVars{'two_parter'} = 'interpreted';
 $template->interpret_and_print();  # Prints "the text is interpreted"

 # Or
 $template = new Text::FillIn();
 $template->get_file('/etc/template_dir/my_template');  # Fetches a file

 # Or
 $template = new Text::FillIn();
 @Text::FillIn::TEMPLATE_PATH = ('.', '/etc/template_dir');  # Where to find templates
 $template->get_file('my_template'); # Gets ./my_template or /etc/template_dir/my_template

=head1 DESCRIPTION

This module provides a class for doing fill-in templates.  These templates may be used
as web pages with dynamic content, e-mail messages with fill-in fields, or whatever other
uses you might think of.  B<Text::FillIn> provides handy methods for fetching files
from the disk, printing a template while interpreting it (also called streaming),
and nested fill-in sections (i.e. expressions like [[ $th[[$thing2]]ing1 ]] are legal).

Note that the version number here is 0.02 - that means that the interface may change
a bit - in particular, the interfaces for accessing the $LEFT_DELIM, $RIGHT_DELIM, 
%HOOK, and @TEMPLATE_PATH variables is probably a little unpredictable in future versions
(see TO_DO below).  I might also change the default HOOKs or something.

In this documentation, I generally use "template" to mean "an object of class Text::FillIn".

=head2 Defining the structure of templates

=over 4

=item * delimiters

B<Text::FillIn> has some special variables that it uses to do its work.  You can set
those variables and customize the way templates get filled in.

The delimiters that set fill-in sections of your form apart from the rest of the
form are generally B<[[> and B<]]>, but they don't have to be, you can set 
them to whatever you want.  So you could do this:

 $Text::FillIn::LEFT_DELIM  = '{';
 $Text::FillIn::RIGHT_DELIM = '}';
 $template->set_text('this is a {$variable} and this is a {&function}.');

Whatever you set the delimiter to, you can put backslashes before them in your
templates, to force them not to be interpreted:

 $template->set_text('some [[$[[$var2]][[$var]]]] and some \[[ text \]]');
 $template->interpret_and_print();
 # Prints "some stuff and some [[ text ]]"

You cannot currently have several different kinds of delimiters in a single template.

=item * interpretation hooks

In order to interpret templates, C<Text::FillIn> needs to know how to treat
different kinds of [[tags]] it finds.  The way it accomplishes this is through
"hook functions."  These are various functions that C<Text::FillIn> will run
when confronted with various kinds of fill-in fields.  There are two 
hooks provided by default:

 $HOOK{'$'} ||= \&find_value;
 $HOOK{'&'} ||= \&run_function;

So if you leave these hooks the way they are, when B<Text::FillIn> sees
some text like "some [[$vars]] and some [[&funk]]", it will run
C<&Text::FillIn::find_value> to find the value of [[$vars]], and it will
run C<&Text::FillIn::run_function> to find the value of [[&funk]].  This
is based on the first non-whitespace character after the delimiter,
which is required to be a non-word character (no letters, numbers, or
underscores).  You can define hooks for any non-word character you want:

 $Text::FillIn::HOOK{'!'} = "main::scream_it";  # or \&scream_it
 $template = new Text::FillIn("some [[!mushrooms]] were in my shoes!");
 sub scream_it {
    my $text = shift;
    return uc($text); # Uppercase-it
 }
 $new_text = $template->interpret();
 # Returns "some MUSHROOMS were in my shoes!"

Every hook function will be passed all the text between the delimiters, without
any surrounding whitespace or the leading identifier (the & or $, or whatever).
Values in %Text::FillIn::HOOK can be either hard references or symbolic references,
but if they are symbolic, they need to use the complete package name and everything.

=item * the default hook functions

The hook functions installed with the shipping version of this module are
C<&Text::FillIn::find_value> and C<&Text::FillIn::run_function>.  They are 
extremely simple.  I suggest you take a look at them to see how they work.
What follows here is a description of how these functions will fill in your
templates.

The C<&find_value> function looks for an entry in a hash called %main::TVars.
So put an entry in this hash if you want it to be available to templates:

 my $template = new Text::FillIn( 'hey, [[$you]]!' );
 $::TVars{'you'} = 'Sam';
 $template->interpret_and_print();  # Prints "hey, Sam!"

The C<&run_function> function looks for a function in the C<TExport> package and
runs it.  The reason it doesn't look in the main package is that you probably
don't want to make all the functions in your program available to the templates
(not that putting all your program's functions in the main package is always
the greatest programming style).  Here are a couple of ways to make functions
available:

 sub TExport::add_numbers {
    my $result;
    foreach (@_) {
       $result += $_;
    }
    return $result;
 }

 #  or, if you like:
 
 package TExport;
 sub add_numbers {
    my $result;
    foreach (@_) {
       $result += $_;
    }
    return $result;
 }

The C<&run_function> function will split the argument string at commas, and pass
the resultant list to your function:

 my $template = new Text::FillIn(
    'Pi is about [[&add_numbers(3,.1,.04,.001,.0006)]]'
 );
 $template->interpret_and_print;


In the original version of C<Text::FillIn>, I didn't provide any hook functions.
I expected people to write their own, partly because I didn't want to stifle
creativity or anything.  I now include hook functions because the ones I give
will probably work okay for most people, and providing them means it's easier
to use the module right out of "the box."  But I hope you won't be afraid to write
your own hooks - if mine don't work well for you, by all means go ahead and
replace them with your own.


=item * template directories

Set @Text::FillIn::TEMPLATE_PATH in your script to point to 
directories with templates in them:

 @Text::FillIn::TEMPLATE_PATH = ('.', '/etc/template_dir')
 $template->get_file('my_template'); # Gets ./my_template or /etc/template_dir/my_template

=back



=head2 Methods

=over 4

=item * new Text::FillIn()

This is the constructor, which means it returns a new object of type B<Text::FillIn>.
If you feed it some text, it will set the template's text to be what you give it:

 $template = new Text::FillIn("some [[$vars]] and some [[&funk]]");

=item * $template->get_file( $filename );

This will look for a template called $filename (in the directories given in 
B<@Text::FillIn::TEMPLATE_PATH>) and slurp it in.  If $filename starts with / , 
then B<Text::FillIn> will treat $filename as an absolute path, and not search 
through the directories for it:

 $template->get_file( "my_template" );
 $template->get_file( "/weird/place/with/template" );

=item * $template->set_text($new_text)

=item * $template->get_text()

These two functions let you access the text of the template.  

=item * $template->interpret()

Returns the interpreted contents of the template:

 $interpreted_text = $template->interpret();

This, along with interpret_and_print, are the main point of this whole module.

=item * $template->interpret_and_print()

Interprets the [[ fill-in parts ]]  of a template and prints the template,
streaming its output as much as possible.  This means that if it encounters
an expression like "[[ stuff [[ more stuff]] ]]", it will fill in [[ more stuff ]],
then use the filled-in value to resolve the value of [[ stuff something ]],
and then print it out.

If it encounters an expression like "stuff1 [[thing1]] stuff2 [[thing2]]",
it will print stuff1, then the value of [[thing1]], then stuff2, then the
value of [[thing2]].  This is as streamed as possible if you want nested
brackets to resolve correctly.

=item * $template->get_property( $name );

=item * $template->set_property( $name, $value );

These two methods let you set arbitrary properties of the template, like
this:

 $template->set_property('color', 'blue');
 # ... some code...
 $color = $template->get_property('color');

The B<Text::FillIn> class doesn't actually pay any attention whatsoever to
the properties - it's purely for your own convenience, so that small changes
in functionality can be achieved in an object-oriented way without having to
subclass B<Text::FillIn>.

=back

=head1 COMMON MISTAKES

If you want to use nested fill-ins on your template, make sure things get 
printed in the order you think they'll be printed.  If you have something like this:
C<[[$var_number_[[&get_number]]]]>, and your &get_number I<prints> a number,
you won't get the results you probably want.  B<Text::FillIn> will print your number,
then try to interpret C<[[$var_number_]]>, which probably won't work.  

The solution is to make &get_number I<return> its number rather than I<print> it.  
Then B<Text::FillIn> will turn C<[[$var_number_[[&get_number]]]]> into 
C<[[$var_number_5]]>, and then print the value of $var_number_5.  That's 
probably what you wanted.

=head1 TO DO

=over 4

=item *

Use autosplit or the SelfLoader module so little used or newly added
functions won't be a burden to programs which don't use them. 

=item *

Make the module more friendly to being sub-classed, in particular by
changing the method for accessing the %HOOK, $RIGHT_DELIM, $LEFT_DELIM, and
@TEMPLATE_PATH variables.

=item *

Think about writing some of the code in C as an extension.  I don't know how
to do this kind of stuff yet, so I haven't - and I don't know whether it's
a good idea either.

=back

=head1 AUTHOR

Ken Williams (ken@forum.swarthmore.edu)

Copyright (c) 1998 Swarthmore College. All rights reserved.
This program is free software; you can redistribute it and/or
modify it under the same terms as Perl itself.

=cut