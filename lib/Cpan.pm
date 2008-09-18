package App::Cpan;

use strict;
use warnings;

=head1 NAME

App::Cpan - easily interact with CPAN from the command line

=head1 SYNOPSIS

	# with arguments and no switches, installs specified modules
	cpan module_name [ module_name ... ]

	# with switches, installs modules with extra behavior
	cpan [-cfimt] module_name [ module_name ... ]

	# with just the dot, install from the distribution in the
	# current directory
	cpan .
	
	# without arguments, starts CPAN.pm shell
	cpan

	# without arguments, but some switches
	cpan [-ahrvACDLO]

=head1 DESCRIPTION

This script provides a command interface (not a shell) to CPAN. At the
moment it uses CPAN.pm to do the work, but it is not a one-shot command
runner for CPAN.pm.

=head2 Meta Options

These options are mutually exclusive, and the script processes them in
this order: [hvCAar].  Once the script finds one, it ignores the others,
and then exits after it finishes the task.  The script ignores any other
command line options.

=over 4

=item -a

Creates the CPAN.pm autobundle with CPAN::Shell->autobundle.

=item -A module [ module ... ]

Shows the primary maintainers for the specified modules

=item -C module [ module ... ]

Show the C<Changes> files for the specified modules

=item -D module [ module ... ]

Show the module details. This prints one line for each out-of-date module
(meaning, modules locally installed but have newer versions on CPAN).
Each line has three columns: module name, local version, and CPAN
version.

=item -j Config.pm

Load the file that has the CPAN configuration data. This should have the
same format as the standard F<CPAN/Config.pm> file, which defines 
C<$CPAN::Config> as an anonymous hash.

=item -J

Dump the configuration in the same format that CPAN.pm uses.

=item -L author [ author ... ]

List the modules by the specified authors.

=item -h

Prints a help message.

=item -O

Show the out-of-date modules.

=item -r

Recompiles dynamically loaded modules with CPAN::Shell->recompile.

=item -v

Print the script version and CPAN.pm version.

=back

=head2 Module options

These options are mutually exclusive, and the script processes them in
alphabetical order. It only processes the first one it finds.

=over 4

=item c

Runs a `make clean` in the specified module's directories.

=item f

Forces the specified action, when it normally would have failed.

=item i

Installed the specified modules.

=item m

Makes the specified modules.

=item t

Runs a `make test` on the specified modules.

=back

=head2 Examples

	# print a help message
	cpan -h

	# print the version numbers
	cpan -v

	# create an autobundle
	cpan -a

	# recompile modules
	cpan -r

	# install modules ( sole -i is optional )
	cpan -i Netscape::Booksmarks Business::ISBN

	# force install modules ( must use -i )
	cpan -fi CGI::Minimal URI

=head1 TO DO


=head1 BUGS

* none noted

=head1 SEE ALSO

Most behaviour, including environment variables and configuration,
comes directly from CPAN.pm.

=cut

use CPAN ();
use Getopt::Std;

our $VERSION = '1.55_01';

# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # 
# set up the order of options that we layer over CPAN::Shell
my @META_OPTIONS = qw( h v C A D O L a r j J );

# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # 
# map switches to method names in CPAN::Shell
my $Default = 'default';

my %CPAN_METHODS = (
	$Default => 'install',
	'c'      => 'clean',
	'f'      => 'force',
	'i'      => 'install',
	'm'      => 'make',
	't'      => 'test',
	);
my @CPAN_OPTIONS = grep { $_ ne $Default } sort keys %CPAN_METHODS;

# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # 
# map switches to the subroutines in this script, along with other information.
# use this stuff instead of hard-coded indices and values
my %Method_table = (
# key => [ sub ref, takes args?, exit value, description ]
	h =>  [ \&_print_help,        0, 0, 'Printing help'                ],
	v =>  [ \&_print_version,     0, 0, 'Printing version'             ],

	j =>  [ \&_load_config,       1, 0, 'Use specified config file'    ],
	J =>  [ \&_dump_config,       0, 0, 'Dump configuration to stdout' ],
	
	C =>  [ \&_show_Changes,      1, 0, 'Showing Changes file'         ],
	A =>  [ \&_show_Author,       1, 0, 'Showing Author'               ],
	D =>  [ \&_show_Details,      1, 0, 'Showing Details'              ],
	O =>  [ \&_show_out_of_date,  0, 0, 'Showing Out of date'          ],
	L =>  [ \&_show_author_mods,  1, 0, 'Showing author mods'          ],
	a =>  [ \&_create_autobundle, 0, 0, 'Creating autobundle'          ],
	r =>  [ \&_recompile,         0, 0, 'Recompiling'                  ],

	c =>  [ \&_default,           1, 0, 'Running `make clean`'         ],
	f =>  [ \&_default,           1, 0, 'Installing with force'        ],
	i =>  [ \&_default,           1, 0, 'Running `make install`'       ],
   'm' => [ \&_default,           1, 0, 'Running `make`'               ],
	t =>  [ \&_default,           1, 0, 'Running `make test`'          ],

	);

my %Method_table_index = (
	code        => 0,
	takes_args  => 1,
	exit_value  => 2,
	description => 3,
	);
	
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # 
# finally, do some argument processing
my @option_order = ( @META_OPTIONS, @CPAN_OPTIONS );

sub _stupid_interface_hack_for_non_rtfmers
	{
	shift @ARGV if( $ARGV[0] eq 'install' and @ARGV > 1 )
	}
	
sub _process_options
	{
	my %options;
	
	# if no arguments, just drop into the shell
	if( 0 == @ARGV ) { CPAN::shell(); exit 0 }

	Getopt::Std::getopts(
		join( '', 
			map {
				$Method_table{ $_ }[ $Method_table_index{takes_args} ] ? "$_:" : $_
				} @option_order 
			), 
				
		\%options 
		);
		
	\%options;
	}

sub _process_setup_options
	{
	my( $class, $options ) = @_;
	
	if( $options->{j} )
		{
		
		
		}
	else
		{
		CPAN::HandleConfig->load;
		}
		
	my $option_count = grep { $options->{$_} } @option_order;
	$option_count -= $options->{'f'}; # don't count force
	
	$options->{i}++ unless $option_count;
	}

# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # 
# if there are no options, set -i (this line fixes RT ticket 16915)



=item run()

Just do it

=cut

sub run
	{
	my $class = shift;
	
	$class->_stupid_interface_hack_for_non_rtfmers;
	
	my $options = $class->_process_options;
	
	$class->_process_setup_options( $options );
	
	foreach my $option ( @option_order )
		{	
		next unless $options->{$option};
		die unless 
			ref $Method_table{$option}[ $Method_table_index{code} ] eq ref sub {};
		
#		print "$Method_table{$option}[ $Method_table_index{description} ] " .
#			"-- ignoring other opitions\n" if $option_count > 1;
		print "$Method_table{$option}[ $Method_table_index{description} ] " .
			"-- ignoring other arguments\n" 
			if( @ARGV && ! $Method_table{$option}[ $Method_table_index{takes_args} ] );
			
		$Method_table{$option}[ $Method_table_index{code} ]->( \ @ARGV, $options );
		
		last;
		}
	}

# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # 
 # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # 
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # 

sub _default
	{
	my( $args, $options ) = @_;
	
	my $switch = '';

	# choose the option that we're going to use
	# we'll deal with 'f' (force) later, so skip it
	foreach my $option ( @CPAN_OPTIONS )
		{
		next if $option eq 'f';
		next unless $options->{$option};
		$switch = $option;
		last;
		}

	# 1. with no switches, but arguments, use the default switch (install)
	# 2. with no switches and no args, start the shell
	# 3. With a switch but no args, die! These switches need arguments.
	   if( not $switch and     @$args ) { $switch = $Default;     }
	elsif( not $switch and not @$args ) { CPAN::shell(); return   }
	elsif(     $switch and not @$args )
		{ die "Nothing to $CPAN_METHODS{$switch}!\n"; }

	# Get and cheeck the method from CPAN::Shell
	my $method = $CPAN_METHODS{$switch};
	die "CPAN.pm cannot $method!\n" unless CPAN::Shell->can( $method );

	# call the CPAN::Shell method, with force if specified
	foreach my $arg ( @$args )
		{
		if( $options->{f} ) { CPAN::Shell->force( $method, $arg ) }
		else                 { CPAN::Shell->$method( $arg )        }
		}

	}

# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # 
sub _print_help
	{
	print STDERR "Use perldoc to read the documentation\n";
	exec "perldoc $0";
	}
	
sub _print_version
	{
	print STDERR "$0 script version $VERSION, CPAN.pm version " . 
		CPAN->VERSION . "\n";
	}
	
sub _create_autobundle
	{
	print "Creating autobundle in ", $CPAN::Config->{cpan_home},
		"/Bundle\n";

	CPAN::Shell->autobundle;
	}

sub _recompiling
	{
	print "Recompiling dynamically-loaded extensions\n";

	CPAN::Shell->recompile;
	}

sub _load_config
	{	
	my $file = shift || '';
	
	# should I clear out any existing config here?
	$CPAN::Config = {};
	delete $INC{'CPAN/Config.pm'};
	die( "Config file [$file] does not exist!\n" ) unless -e $file;
	
	my $rc = eval "require '$file'";

	# CPAN::HandleConfig::require_myconfig_or_config looks for this
	$INC{'CPAN/MyConfig.pm'} = 'fake out!';
	
	# CPAN::HandleConfig::load looks for this
	$CPAN::Config_loaded = 'fake out';
	
	die( "Could not load [$file]: $@\n") unless $rc;
	
	return 1;
	}

sub _dump_config
	{
	my $args = shift;
	use Data::Dumper;
	
	my $fh = $args->[0] || \*STDOUT;
		
	my $dd = Data::Dumper->new( 
		[$CPAN::Config], 
		['$CPAN::Config'] 
		);
		
	print $fh $dd->Dump, "\n1;\n__END__\n";
	
	return 1;
	}
	
sub _show_Changes
	{
	my $args = shift;
	
	foreach my $arg ( @$args )
		{
		print "Checking $arg\n";
		my $module = CPAN::Shell->expand( "Module", $arg );
		
		next unless $module->inst_file;
		#next if $module->uptodate;
	
		( my $id = $module->id() ) =~ s/::/\-/;
	
		my $url = "http://search.cpan.org/~" . lc( $module->userid ) . "/" .
			$id . "-" . $module->cpan_version() . "/";
	
		#print "URL: $url\n";
		_get_changes_file($url);
		}
	}	
	
sub _get_changes_file
	{
	die "Reading Changes files requires LWP::Simple and URI\n"
		unless eval { require LWP::Simple; require URI; };
	
    my $url = shift;

    my $content = LWP::Simple::get( $url );
    print "Got $url ...\n" if defined $content;
	#print $content;
	
	my( $change_link ) = $content =~ m|<a href="(.*?)">Changes</a>|gi;
	
	my $changes_url = URI->new_abs( $change_link, $url );
 	#print "change link is: $changes_url\n";
	my $changes =  LWP::Simple::get( $changes_url );
	#print "change text is: " . $change_link->text() . "\n";
	print $changes;
	}
	
sub _show_Author
	{
	my $args = shift;
	
	foreach my $arg ( @$args )
		{
		my $module = CPAN::Shell->expand( "Module", $arg );
		my $author = CPAN::Shell->expand( "Author", $module->userid );
	
		next unless $module->userid;
	
		printf "%-25s %-8s %-25s %s\n", 
			$arg, $module->userid, $author->email, $author->fullname;
		}
	}	

sub _show_Details
	{
	my $args = shift;
	
	foreach my $arg ( @$args )
		{
		my $module = CPAN::Shell->expand( "Module", $arg );
		my $author = CPAN::Shell->expand( "Author", $module->userid );
	
		next unless $module->userid;
	
		print "$arg\n", "-" x 73, "\n\t";
		print join "\n\t",
			$module->description ? $module->description : "(no description)",
			$module->cpan_file,
			$module->inst_file,
			'Installed: ' . $module->inst_version,
			'CPAN:      ' . $module->cpan_version . '  ' .
				($module->uptodate ? "" : "Not ") . "up to date",
			$author->fullname . " (" . $module->userid . ")",
			$author->email;
		print "\n\n";
		
		}
	}	

sub _show_out_of_date
	{
	my @modules = CPAN::Shell->expand( "Module", "/./" );
		
	printf "%-40s  %6s  %6s\n", "Module Name", "Local", "CPAN";
	print "-" x 73, "\n";
	
	foreach my $module ( @modules )
		{
		next unless $module->inst_file;
		next if $module->uptodate;
		printf "%-40s  %.4f  %.4f\n",
			$module->id, 
			$module->inst_version ? $module->inst_version : '', 
			$module->cpan_version;
		}

	}

sub _show_author_mods
	{
	my $args = shift;

	my %hash = map { lc $_, 1 } @$args;
	
	my @modules = CPAN::Shell->expand( "Module", "/./" );
	
	foreach my $module ( @modules )
		{
		next unless exists $hash{ lc $module->userid };
		print $module->id, "\n";
		}
	
	}
	
1;

=head1 SOURCE AVAILABILITY

This code is in Github:

	git://github.com/briandfoy/cpan_script.git

=head1 CREDITS

Japheth Cleaver added the bits to allow a forced install (-f).

Jim Brandt suggest and provided the initial implementation for the
up-to-date and Changes features.

Adam Kennedy pointed out that exit() causes problems on Windows
where this script ends up with a .bat extension

=head1 AUTHOR

brian d foy, C<< <bdfoy@cpan.org> >>

=head1 COPYRIGHT

Copyright (c) 2001-2008, brian d foy, All Rights Reserved.

You may redistribute this under the same terms as Perl itself.

=cut