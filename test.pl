# Before `make install' is performed this script should be runnable with
# `make test'. After `make install' it should work as `perl test.pl'

######################### We start with some black magic to print on failure.

# Change 1..1 below to 1..last_test_to_print .
# (It may become useful if the test is moved to ./t subdirectory.)

BEGIN { $| = 1; print "1..21\n"; }
END {print "not ok 1\n" unless $loaded;}
use Text::FillIn;
$loaded = 1;
print "ok 1\n";

######################### End of black magic.

# Insert your test code below (better if it prints "ok 13"
# (correspondingly "not ok 13") depending on the success of chunk 13
# of the test code):

sub report_result {
	$TEST_NUM ||= 2; 
	print ( $_[0] ? "ok $TEST_NUM\n" : "not ok $TEST_NUM\n" );
	$TEST_NUM++;
}

# The variables for interpolation
$TVars{'var'} = 'text';
$TVars{'nestedtext'} = 'coconuts';
$TVars{'more_var'} = 'donuts';
$TVars{'var2'} = 'nested';
$TVars{'text\\]]'} = 'garbage';

#@TVars{'var',  'nestedtext', 'more_var', 'var2',   'text\\]]'} =
#      ('text', 'coconuts',   'donuts',   'nested', 'garbage');

# 2,3
&test_both('some [[$var]] and so on' => 'some text and so on');

# 4,5
&test_both('some [[ $nested[[$var]] ]] flambe' => 'some coconuts flambe');

# 6,7
&test_both('[[$var]]' => 'text');

# 8,9
&test_both('[[ $var ]]' => 'text');

# 10,11
&test_both('an example of [[$var]] and [[$more_var]] together' =>
             'an example of text and donuts together');

# 12,13
&test_both('some [[$[[$var2]][[$var]]]] and some \\[[ text \\]]' =>
             'some coconuts and some [[ text ]]');

# 14,15
&test_both('some [[$[[$var2]][[$var]]]] and some [[ $text\\]] ]]' =>
             'some coconuts and some garbage');

# 16,17
&test_both('some [[&func1()]]?' => 'some snails?');

# 18,19
&test_both('some [[&func2(star,studded)]] SNAILS?' => 'some STAR*STUDDED SNAILS?');

# 20,21
&test_both('Pi is about [[&add_numbers(3,.1,.04,.001,.0006)]]' => 'Pi is about 3.1416');

###################################################################

sub test_both {
   &test_interpret(@_);
   &test_interpret(@_);
}

sub test_interpret {
   my $debug = 0;
   my ($raw_text, $cooked_text) = @_;
   my $template = new Text::FillIn($raw_text);
   my $result = $template->interpret;

   print ("--$TEST_NUM--\n$raw_text\n--$TEST_NUM--\n$result\n") if $debug;

   &report_result( $result eq $cooked_text );
}

sub test_print {
   my $debug = 0;
   my ($raw_text, $cooked_text) = @_;
   my $template = new Text::FillIn($raw_text);
   my $file = '/tmp/template_test';
   
   open (TEMP, ">$file") or die $!;
   my $prev_select = select TEMP;
   $template->interpret_and_print();
   close TEMP;
   select $prev_select;

   my $result = `cat /tmp/template_test`;
   unlink $file or die $!;

   print ("--$TEST_NUM--\n$raw_text\n--$TEST_NUM--\n$result\n") if $debug;

   &report_result( $result eq $cooked_text );
}

sub TExport::func1 {
   return "snails";
}

sub TExport::func2 {
   return join '*', map {uc} @_;
}

sub TExport::add_numbers {
  my $result;
  foreach (@_) {
     $result += $_;
  }
  return $result;
}
		    
