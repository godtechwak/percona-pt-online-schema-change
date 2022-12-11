#!/usr/bin/perl5.30

# This program is part of Percona Toolkit: http://www.percona.com/software/
# See "COPYRIGHT, LICENSE, AND WARRANTY" at the end of this file for legal
# notices and disclaimers.

use strict;
use warnings FATAL => 'all';

# This tool is "fat-packed": most of its dependent modules are embedded
# in this file.  Setting %INC to this file for each module makes Perl aware
# of this so it will not try to load the module from @INC.  See the tool's
# documentation for a full list of dependencies.
BEGIN {
   $INC{$_} = __FILE__ for map { (my $pkg = "$_.pm") =~ s!::!/!g; $pkg } (qw(
      Percona::Toolkit
      VersionCompare
      OptionParser
      Lmo::Utils
      Lmo::Meta
      Lmo::Object
      Lmo::Types
      Lmo
      VersionParser
      DSNParser
      Daemon
      Quoter
      TableNibbler
      TableParser
      Progress
      Retry
      Cxn
      MasterSlave
      ReplicaLagWaiter
      FlowControlWaiter
      MySQLStatusWaiter
      WeightedAvgRate
      NibbleIterator
      Transformers
      CleanupTask
      IndexLength
      HTTP::Micro
      VersionCheck
      Percona::XtraDB::Cluster
   ));
}

# ###########################################################################
# Percona::Toolkit package
# This package is a copy without comments from the original.  The original
# with comments and its test file can be found in the GitHub repository at,
#   lib/Percona/Toolkit.pm
#   t/lib/Percona/Toolkit.t
# See https://github.com/percona/percona-toolkit for more information.
# ###########################################################################
{
package Percona::Toolkit;

our $VERSION = '3.5.0';

use strict;
use warnings FATAL => 'all';
use English qw(-no_match_vars);
use constant PTDEBUG => $ENV{PTDEBUG} || 0;

use Carp qw(carp cluck);
use Data::Dumper qw();

require Exporter;
our @ISA         = qw(Exporter);
our @EXPORT_OK   = qw(
   have_required_args
   Dumper
   _d
);

sub have_required_args {
   my ($args, @required_args) = @_;
   my $have_required_args = 1;
   foreach my $arg ( @required_args ) {
      if ( !defined $args->{$arg} ) {
         $have_required_args = 0;
         carp "Argument $arg is not defined";
      }
   }
   cluck unless $have_required_args;  # print backtrace
   return $have_required_args;
}

sub Dumper {
   local $Data::Dumper::Indent    = 1;
   local $Data::Dumper::Sortkeys  = 1;
   local $Data::Dumper::Quotekeys = 0;
   Data::Dumper::Dumper(@_);
}

sub _d {
   my ($package, undef, $line) = caller 0;
   @_ = map { (my $temp = $_) =~ s/\n/\n# /g; $temp; }
        map { defined $_ ? $_ : 'undef' }
        @_;
   print STDERR "# $package:$line $PID ", join(' ', @_), "\n";
}

1;
}
# ###########################################################################
# End Percona::Toolkit package
# ###########################################################################
#

# ###########################################################################
# VersionCompare package
# This package is a copy without comments from the original.  The original
# with comments and its test file can be found in the Bazaar repository at,
#   lib/VersionCompare.pm
#   t/lib/VersionCompare.t
# See https://launchpad.net/percona-toolkit for more information.
# ###########################################################################
{
package VersionCompare;

use strict;
use English qw(-no_match_vars);
use constant PTDEBUG => $ENV{PTDEBUG} || 0;

sub cmp {
   my ($v1, $v2) = @_;

   $v1 =~ s/[^\d\.]//;
   $v2 =~ s/[^\d\.]//;

   my @a = ( $v1 =~ /(\d+)\.?/g );
   my @b = ( $v2 =~ /(\d+)\.?/g );
   foreach my $n1 (@a) {
      $n1 += 0; #convert to number
      if (!@b) {
         return 1;
      }
      my $n2 = shift @b;
      $n2 += 0; # convert to number
      if ($n1 == $n2) {
          next;
      }
      else {
         return $n1 <=> $n2;
      }
   }
   return @b ? -1 : 0;
}


1;
}
# ###########################################################################
# End VersionCompare package
# ###########################################################################

# ###########################################################################
# OptionParser package
# This package is a copy without comments from the original.  The original
# with comments and its test file can be found in the Bazaar repository at,
#   lib/OptionParser.pm
#   t/lib/OptionParser.t
# See https://launchpad.net/percona-toolkit for more information.
# ###########################################################################
{
package OptionParser;

use strict;
use warnings FATAL => 'all';
use English qw(-no_match_vars);
use constant PTDEBUG => $ENV{PTDEBUG} || 0;

use List::Util qw(max);
use Getopt::Long;
use Data::Dumper;

my $POD_link_re = '[LC]<"?([^">]+)"?>';

sub new {
   my ( $class, %args ) = @_;
   my @required_args = qw();
   foreach my $arg ( @required_args ) {
      die "I need a $arg argument" unless $args{$arg};
   }

   my ($program_name) = $PROGRAM_NAME =~ m/([.A-Za-z-]+)$/;
   $program_name ||= $PROGRAM_NAME;
   my $home = $ENV{HOME} || $ENV{HOMEPATH} || $ENV{USERPROFILE} || '.';

   my %attributes = (
      'type'       => 1,
      'short form' => 1,
      'group'      => 1,
      'default'    => 1,
      'cumulative' => 1,
      'negatable'  => 1,
      'repeatable' => 1,  # means it can be specified more than once
   );

   my $self = {
      head1             => 'OPTIONS',        # These args are used internally
      skip_rules        => 0,                # to instantiate another Option-
      item              => '--(.*)',         # Parser obj that parses the
      attributes        => \%attributes,     # DSN OPTIONS section.  Tools
      parse_attributes  => \&_parse_attribs, # don't tinker with these args.

      %args,

      strict            => 1,  # disabled by a special rule
      program_name      => $program_name,
      opts              => {},
      got_opts          => 0,
      short_opts        => {},
      defaults          => {},
      groups            => {},
      allowed_groups    => {},
      errors            => [],
      rules             => [],  # desc of rules for --help
      mutex             => [],  # rule: opts are mutually exclusive
      atleast1          => [],  # rule: at least one opt is required
      disables          => {},  # rule: opt disables other opts
      defaults_to       => {},  # rule: opt defaults to value of other opt
      DSNParser         => undef,
      default_files     => [
         "/etc/percona-toolkit/percona-toolkit.conf",
         "/etc/percona-toolkit/$program_name.conf",
         "$home/.percona-toolkit.conf",
         "$home/.$program_name.conf",
      ],
      types             => {
         string => 's', # standard Getopt type
         int    => 'i', # standard Getopt type
         float  => 'f', # standard Getopt type
         Hash   => 'H', # hash, formed from a comma-separated list
         hash   => 'h', # hash as above, but only if a value is given
         Array  => 'A', # array, similar to Hash
         array  => 'a', # array, similar to hash
         DSN    => 'd', # DSN
         size   => 'z', # size with kMG suffix (powers of 2^10)
         time   => 'm', # time, with an optional suffix of s/h/m/d
      },
   };

   return bless $self, $class;
}

sub get_specs {
   my ( $self, $file ) = @_;
   $file ||= $self->{file} || __FILE__;
   my @specs = $self->_pod_to_specs($file);
   $self->_parse_specs(@specs);

   open my $fh, "<", $file or die "Cannot open $file: $OS_ERROR";
   my $contents = do { local $/ = undef; <$fh> };
   close $fh;
   if ( $contents =~ m/^=head1 DSN OPTIONS/m ) {
      PTDEBUG && _d('Parsing DSN OPTIONS');
      my $dsn_attribs = {
         dsn  => 1,
         copy => 1,
      };
      my $parse_dsn_attribs = sub {
         my ( $self, $option, $attribs ) = @_;
         map {
            my $val = $attribs->{$_};
            if ( $val ) {
               $val    = $val eq 'yes' ? 1
                       : $val eq 'no'  ? 0
                       :                 $val;
               $attribs->{$_} = $val;
            }
         } keys %$attribs;
         return {
            key => $option,
            %$attribs,
         };
      };
      my $dsn_o = new OptionParser(
         description       => 'DSN OPTIONS',
         head1             => 'DSN OPTIONS',
         dsn               => 0,         # XXX don't infinitely recurse!
         item              => '\* (.)',  # key opts are a single character
         skip_rules        => 1,         # no rules before opts
         attributes        => $dsn_attribs,
         parse_attributes  => $parse_dsn_attribs,
      );
      my @dsn_opts = map {
         my $opts = {
            key  => $_->{spec}->{key},
            dsn  => $_->{spec}->{dsn},
            copy => $_->{spec}->{copy},
            desc => $_->{desc},
         };
         $opts;
      } $dsn_o->_pod_to_specs($file);
      $self->{DSNParser} = DSNParser->new(opts => \@dsn_opts);
   }

   if ( $contents =~ m/^=head1 VERSION\n\n^(.+)$/m ) {
      $self->{version} = $1;
      PTDEBUG && _d($self->{version});
   }

   return;
}

sub DSNParser {
   my ( $self ) = @_;
   return $self->{DSNParser};
};

sub get_defaults_files {
   my ( $self ) = @_;
   return @{$self->{default_files}};
}

sub _pod_to_specs {
   my ( $self, $file ) = @_;
   $file ||= $self->{file} || __FILE__;
   open my $fh, '<', $file or die "Cannot open $file: $OS_ERROR";

   my @specs = ();
   my @rules = ();
   my $para;

   local $INPUT_RECORD_SEPARATOR = '';
   while ( $para = <$fh> ) {
      next unless $para =~ m/^=head1 $self->{head1}/;
      last;
   }

   while ( $para = <$fh> ) {
      last if $para =~ m/^=over/;
      next if $self->{skip_rules};
      chomp $para;
      $para =~ s/\s+/ /g;
      $para =~ s/$POD_link_re/$1/go;
      PTDEBUG && _d('Option rule:', $para);
      push @rules, $para;
   }

   die "POD has no $self->{head1} section" unless $para;

   do {
      if ( my ($option) = $para =~ m/^=item $self->{item}/ ) {
         chomp $para;
         PTDEBUG && _d($para);
         my %attribs;

         $para = <$fh>; # read next paragraph, possibly attributes

         if ( $para =~ m/: / ) { # attributes
            $para =~ s/\s+\Z//g;
            %attribs = map {
                  my ( $attrib, $val) = split(/: /, $_);
                  die "Unrecognized attribute for --$option: $attrib"
                     unless $self->{attributes}->{$attrib};
                  ($attrib, $val);
               } split(/; /, $para);
            if ( $attribs{'short form'} ) {
               $attribs{'short form'} =~ s/-//;
            }
            $para = <$fh>; # read next paragraph, probably short help desc
         }
         else {
            PTDEBUG && _d('Option has no attributes');
         }

         $para =~ s/\s+\Z//g;
         $para =~ s/\s+/ /g;
         $para =~ s/$POD_link_re/$1/go;

         $para =~ s/\.(?:\n.*| [A-Z].*|\Z)//s;
         PTDEBUG && _d('Short help:', $para);

         die "No description after option spec $option" if $para =~ m/^=item/;

         if ( my ($base_option) =  $option =~ m/^\[no\](.*)/ ) {
            $option = $base_option;
            $attribs{'negatable'} = 1;
         }

         push @specs, {
            spec  => $self->{parse_attributes}->($self, $option, \%attribs),
            desc  => $para
               . (defined $attribs{default} ? " (default $attribs{default})" : ''),
            group => ($attribs{'group'} ? $attribs{'group'} : 'default'),
            attributes => \%attribs
         };
      }
      while ( $para = <$fh> ) {
         last unless $para;
         if ( $para =~ m/^=head1/ ) {
            $para = undef; # Can't 'last' out of a do {} block.
            last;
         }
         last if $para =~ m/^=item /;
      }
   } while ( $para );

   die "No valid specs in $self->{head1}" unless @specs;

   close $fh;
   return @specs, @rules;
}

sub _parse_specs {
   my ( $self, @specs ) = @_;
   my %disables; # special rule that requires deferred checking

   foreach my $opt ( @specs ) {
      if ( ref $opt ) { # It's an option spec, not a rule.
         PTDEBUG && _d('Parsing opt spec:',
            map { ($_, '=>', $opt->{$_}) } keys %$opt);

         my ( $long, $short ) = $opt->{spec} =~ m/^([\w-]+)(?:\|([^!+=]*))?/;
         if ( !$long ) {
            die "Cannot parse long option from spec $opt->{spec}";
         }
         $opt->{long} = $long;

         die "Duplicate long option --$long" if exists $self->{opts}->{$long};
         $self->{opts}->{$long} = $opt;

         if ( length $long == 1 ) {
            PTDEBUG && _d('Long opt', $long, 'looks like short opt');
            $self->{short_opts}->{$long} = $long;
         }

         if ( $short ) {
            die "Duplicate short option -$short"
               if exists $self->{short_opts}->{$short};
            $self->{short_opts}->{$short} = $long;
            $opt->{short} = $short;
         }
         else {
            $opt->{short} = undef;
         }

         $opt->{is_negatable}  = $opt->{spec} =~ m/!/        ? 1 : 0;
         $opt->{is_cumulative} = $opt->{spec} =~ m/\+/       ? 1 : 0;
         $opt->{is_repeatable} = $opt->{attributes}->{repeatable} ? 1 : 0;
         $opt->{is_required}   = $opt->{desc} =~ m/required/ ? 1 : 0;

         $opt->{group} ||= 'default';
         $self->{groups}->{ $opt->{group} }->{$long} = 1;

         $opt->{value} = undef;
         $opt->{got}   = 0;

         my ( $type ) = $opt->{spec} =~ m/=(.)/;
         $opt->{type} = $type;
         PTDEBUG && _d($long, 'type:', $type);


         $opt->{spec} =~ s/=./=s/ if ( $type && $type =~ m/[HhAadzm]/ );

         if ( (my ($def) = $opt->{desc} =~ m/default\b(?: ([^)]+))?/) ) {
            $self->{defaults}->{$long} = defined $def ? $def : 1;
            PTDEBUG && _d($long, 'default:', $def);
         }

         if ( $long eq 'config' ) {
            $self->{defaults}->{$long} = join(',', $self->get_defaults_files());
         }

         if ( (my ($dis) = $opt->{desc} =~ m/(disables .*)/) ) {
            $disables{$long} = $dis;
            PTDEBUG && _d('Deferring check of disables rule for', $opt, $dis);
         }

         $self->{opts}->{$long} = $opt;
      }
      else { # It's an option rule, not a spec.
         PTDEBUG && _d('Parsing rule:', $opt);
         push @{$self->{rules}}, $opt;
         my @participants = $self->_get_participants($opt);
         my $rule_ok = 0;

         if ( $opt =~ m/mutually exclusive|one and only one/ ) {
            $rule_ok = 1;
            push @{$self->{mutex}}, \@participants;
            PTDEBUG && _d(@participants, 'are mutually exclusive');
         }
         if ( $opt =~ m/at least one|one and only one/ ) {
            $rule_ok = 1;
            push @{$self->{atleast1}}, \@participants;
            PTDEBUG && _d(@participants, 'require at least one');
         }
         if ( $opt =~ m/default to/ ) {
            $rule_ok = 1;
            $self->{defaults_to}->{$participants[0]} = $participants[1];
            PTDEBUG && _d($participants[0], 'defaults to', $participants[1]);
         }
         if ( $opt =~ m/restricted to option groups/ ) {
            $rule_ok = 1;
            my ($groups) = $opt =~ m/groups ([\w\s\,]+)/;
            my @groups = split(',', $groups);
            %{$self->{allowed_groups}->{$participants[0]}} = map {
               s/\s+//;
               $_ => 1;
            } @groups;
         }
         if( $opt =~ m/accepts additional command-line arguments/ ) {
            $rule_ok = 1;
            $self->{strict} = 0;
            PTDEBUG && _d("Strict mode disabled by rule");
         }

         die "Unrecognized option rule: $opt" unless $rule_ok;
      }
   }

   foreach my $long ( keys %disables ) {
      my @participants = $self->_get_participants($disables{$long});
      $self->{disables}->{$long} = \@participants;
      PTDEBUG && _d('Option', $long, 'disables', @participants);
   }

   return;
}

sub _get_participants {
   my ( $self, $str ) = @_;
   my @participants;
   foreach my $long ( $str =~ m/--(?:\[no\])?([\w-]+)/g ) {
      die "Option --$long does not exist while processing rule $str"
         unless exists $self->{opts}->{$long};
      push @participants, $long;
   }
   PTDEBUG && _d('Participants for', $str, ':', @participants);
   return @participants;
}

sub opts {
   my ( $self ) = @_;
   my %opts = %{$self->{opts}};
   return %opts;
}

sub short_opts {
   my ( $self ) = @_;
   my %short_opts = %{$self->{short_opts}};
   return %short_opts;
}

sub set_defaults {
   my ( $self, %defaults ) = @_;
   $self->{defaults} = {};
   foreach my $long ( keys %defaults ) {
      die "Cannot set default for nonexistent option $long"
         unless exists $self->{opts}->{$long};
      $self->{defaults}->{$long} = $defaults{$long};
      PTDEBUG && _d('Default val for', $long, ':', $defaults{$long});
   }
   return;
}

sub get_defaults {
   my ( $self ) = @_;
   return $self->{defaults};
}

sub get_groups {
   my ( $self ) = @_;
   return $self->{groups};
}

sub _set_option {
   my ( $self, $opt, $val ) = @_;
   my $long = exists $self->{opts}->{$opt}       ? $opt
            : exists $self->{short_opts}->{$opt} ? $self->{short_opts}->{$opt}
            : die "Getopt::Long gave a nonexistent option: $opt";
   $opt = $self->{opts}->{$long};
   if ( $opt->{is_cumulative} ) {
      $opt->{value}++;
   }
   elsif ( ($opt->{type} || '') eq 's' && $val =~ m/^--?(.+)/ ) {
      my $next_opt = $1;
      if (    exists $self->{opts}->{$next_opt}
           || exists $self->{short_opts}->{$next_opt} ) {
         $self->save_error("--$long requires a string value");
         return;
      }
      else {
         if ($opt->{is_repeatable}) {
            push @{$opt->{value}} , $val;
         }
         else {
            $opt->{value} = $val;
         }
      }
   }
   else {
      if ($opt->{is_repeatable}) {
         push @{$opt->{value}} , $val;
      }
      else {
         $opt->{value} = $val;
      }
   }
   $opt->{got} = 1;
   PTDEBUG && _d('Got option', $long, '=', $val);
}

sub get_opts {
   my ( $self ) = @_;

   foreach my $long ( keys %{$self->{opts}} ) {
      $self->{opts}->{$long}->{got} = 0;
      $self->{opts}->{$long}->{value}
         = exists $self->{defaults}->{$long}       ? $self->{defaults}->{$long}
         : $self->{opts}->{$long}->{is_cumulative} ? 0
         : undef;
   }
   $self->{got_opts} = 0;

   $self->{errors} = [];

   if ( @ARGV && $ARGV[0] =~/^--config=/ ) {
      $ARGV[0] = substr($ARGV[0],9);
      $ARGV[0] =~ s/^'(.*)'$/$1/;
      $ARGV[0] =~ s/^"(.*)"$/$1/;
      $self->_set_option('config', shift @ARGV);
   }
   if ( @ARGV && $ARGV[0] eq "--config" ) {
      shift @ARGV;
      $self->_set_option('config', shift @ARGV);
   }
   if ( $self->has('config') ) {
      my @extra_args;
      foreach my $filename ( split(',', $self->get('config')) ) {
         eval {
            push @extra_args, $self->_read_config_file($filename);
         };
         if ( $EVAL_ERROR ) {
            if ( $self->got('config') ) {
               die $EVAL_ERROR;
            }
            elsif ( PTDEBUG ) {
               _d($EVAL_ERROR);
            }
         }
      }
      unshift @ARGV, @extra_args;
   }

   Getopt::Long::Configure('no_ignore_case', 'bundling');
   GetOptions(
      map    { $_->{spec} => sub { $self->_set_option(@_); } }
      grep   { $_->{long} ne 'config' } # --config is handled specially above.
      values %{$self->{opts}}
   ) or $self->save_error('Error parsing options');

   if ( exists $self->{opts}->{version} && $self->{opts}->{version}->{got} ) {
      if ( $self->{version} ) {
         print $self->{version}, "\n";
         exit 0;
      }
      else {
         print "Error parsing version.  See the VERSION section of the tool's documentation.\n";
         exit 1;
      }
   }

   if ( @ARGV && $self->{strict} ) {
      $self->save_error("Unrecognized command-line options @ARGV");
   }

   foreach my $mutex ( @{$self->{mutex}} ) {
      my @set = grep { $self->{opts}->{$_}->{got} } @$mutex;
      if ( @set > 1 ) {
         my $err = join(', ', map { "--$self->{opts}->{$_}->{long}" }
                      @{$mutex}[ 0 .. scalar(@$mutex) - 2] )
                 . ' and --'.$self->{opts}->{$mutex->[-1]}->{long}
                 . ' are mutually exclusive.';
         $self->save_error($err);
      }
   }

   foreach my $required ( @{$self->{atleast1}} ) {
      my @set = grep { $self->{opts}->{$_}->{got} } @$required;
      if ( @set == 0 ) {
         my $err = join(', ', map { "--$self->{opts}->{$_}->{long}" }
                      @{$required}[ 0 .. scalar(@$required) - 2] )
                 .' or --'.$self->{opts}->{$required->[-1]}->{long};
         $self->save_error("Specify at least one of $err");
      }
   }

   $self->_check_opts( keys %{$self->{opts}} );
   $self->{got_opts} = 1;
   return;
}

sub _check_opts {
   my ( $self, @long ) = @_;
   my $long_last = scalar @long;
   while ( @long ) {
      foreach my $i ( 0..$#long ) {
         my $long = $long[$i];
         next unless $long;
         my $opt  = $self->{opts}->{$long};
         if ( $opt->{got} ) {
            if ( exists $self->{disables}->{$long} ) {
               my @disable_opts = @{$self->{disables}->{$long}};
               map { $self->{opts}->{$_}->{value} = undef; } @disable_opts;
               PTDEBUG && _d('Unset options', @disable_opts,
                  'because', $long,'disables them');
            }

            if ( exists $self->{allowed_groups}->{$long} ) {

               my @restricted_groups = grep {
                  !exists $self->{allowed_groups}->{$long}->{$_}
               } keys %{$self->{groups}};

               my @restricted_opts;
               foreach my $restricted_group ( @restricted_groups ) {
                  RESTRICTED_OPT:
                  foreach my $restricted_opt (
                     keys %{$self->{groups}->{$restricted_group}} )
                  {
                     next RESTRICTED_OPT if $restricted_opt eq $long;
                     push @restricted_opts, $restricted_opt
                        if $self->{opts}->{$restricted_opt}->{got};
                  }
               }

               if ( @restricted_opts ) {
                  my $err;
                  if ( @restricted_opts == 1 ) {
                     $err = "--$restricted_opts[0]";
                  }
                  else {
                     $err = join(', ',
                               map { "--$self->{opts}->{$_}->{long}" }
                               grep { $_ }
                               @restricted_opts[0..scalar(@restricted_opts) - 2]
                            )
                          . ' or --'.$self->{opts}->{$restricted_opts[-1]}->{long};
                  }
                  $self->save_error("--$long is not allowed with $err");
               }
            }

         }
         elsif ( $opt->{is_required} ) {
            $self->save_error("Required option --$long must be specified");
         }

         $self->_validate_type($opt);
         if ( $opt->{parsed} ) {
            delete $long[$i];
         }
         else {
            PTDEBUG && _d('Temporarily failed to parse', $long);
         }
      }

      die "Failed to parse options, possibly due to circular dependencies"
         if @long == $long_last;
      $long_last = @long;
   }

   return;
}

sub _validate_type {
   my ( $self, $opt ) = @_;
   return unless $opt;

   if ( !$opt->{type} ) {
      $opt->{parsed} = 1;
      return;
   }

   my $val = $opt->{value};

   if ( $val && $opt->{type} eq 'm' ) {  # type time
      PTDEBUG && _d('Parsing option', $opt->{long}, 'as a time value');
      my ( $prefix, $num, $suffix ) = $val =~ m/([+-]?)(\d+)([a-z])?$/;
      if ( !$suffix ) {
         my ( $s ) = $opt->{desc} =~ m/\(suffix (.)\)/;
         $suffix = $s || 's';
         PTDEBUG && _d('No suffix given; using', $suffix, 'for',
            $opt->{long}, '(value:', $val, ')');
      }
      if ( $suffix =~ m/[smhd]/ ) {
         $val = $suffix eq 's' ? $num            # Seconds
              : $suffix eq 'm' ? $num * 60       # Minutes
              : $suffix eq 'h' ? $num * 3600     # Hours
              :                  $num * 86400;   # Days
         $opt->{value} = ($prefix || '') . $val;
         PTDEBUG && _d('Setting option', $opt->{long}, 'to', $val);
      }
      else {
         $self->save_error("Invalid time suffix for --$opt->{long}");
      }
   }
   elsif ( $val && $opt->{type} eq 'd' ) {  # type DSN
      PTDEBUG && _d('Parsing option', $opt->{long}, 'as a DSN');
      my $prev = {};
      my $from_key = $self->{defaults_to}->{ $opt->{long} };
      if ( $from_key ) {
         PTDEBUG && _d($opt->{long}, 'DSN copies from', $from_key, 'DSN');
         if ( $self->{opts}->{$from_key}->{parsed} ) {
            $prev = $self->{opts}->{$from_key}->{value};
         }
         else {
            PTDEBUG && _d('Cannot parse', $opt->{long}, 'until',
               $from_key, 'parsed');
            return;
         }
      }
      my $defaults = $self->{DSNParser}->parse_options($self);
      if (!$opt->{attributes}->{repeatable}) {
          $opt->{value} = $self->{DSNParser}->parse($val, $prev, $defaults);
      } else {
          my $values = [];
          for my $dsn_string (@$val) {
              push @$values, $self->{DSNParser}->parse($dsn_string, $prev, $defaults);
          }
          $opt->{value} = $values;
      }
   }
   elsif ( $val && $opt->{type} eq 'z' ) {  # type size
      PTDEBUG && _d('Parsing option', $opt->{long}, 'as a size value');
      $self->_parse_size($opt, $val);
   }
   elsif ( $opt->{type} eq 'H' || (defined $val && $opt->{type} eq 'h') ) {
      $opt->{value} = { map { $_ => 1 } split(/(?<!\\),\s*/, ($val || '')) };
   }
   elsif ( $opt->{type} eq 'A' || (defined $val && $opt->{type} eq 'a') ) {
      $opt->{value} = [ split(/(?<!\\),\s*/, ($val || '')) ];
   }
   else {
      PTDEBUG && _d('Nothing to validate for option',
         $opt->{long}, 'type', $opt->{type}, 'value', $val);
   }

   $opt->{parsed} = 1;
   return;
}

sub get {
   my ( $self, $opt ) = @_;
   my $long = (length $opt == 1 ? $self->{short_opts}->{$opt} : $opt);
   die "Option $opt does not exist"
      unless $long && exists $self->{opts}->{$long};
   return $self->{opts}->{$long}->{value};
}

sub got {
   my ( $self, $opt ) = @_;
   my $long = (length $opt == 1 ? $self->{short_opts}->{$opt} : $opt);
   die "Option $opt does not exist"
      unless $long && exists $self->{opts}->{$long};
   return $self->{opts}->{$long}->{got};
}

sub has {
   my ( $self, $opt ) = @_;
   my $long = (length $opt == 1 ? $self->{short_opts}->{$opt} : $opt);
   return defined $long ? exists $self->{opts}->{$long} : 0;
}

sub set {
   my ( $self, $opt, $val ) = @_;
   my $long = (length $opt == 1 ? $self->{short_opts}->{$opt} : $opt);
   die "Option $opt does not exist"
      unless $long && exists $self->{opts}->{$long};
   $self->{opts}->{$long}->{value} = $val;
   return;
}

sub save_error {
   my ( $self, $error ) = @_;
   push @{$self->{errors}}, $error;
   return;
}

sub errors {
   my ( $self ) = @_;
   return $self->{errors};
}

sub usage {
   my ( $self ) = @_;
   warn "No usage string is set" unless $self->{usage}; # XXX
   return "Usage: " . ($self->{usage} || '') . "\n";
}

sub descr {
   my ( $self ) = @_;
   warn "No description string is set" unless $self->{description}; # XXX
   my $descr  = ($self->{description} || $self->{program_name} || '')
              . "  For more details, please use the --help option, "
              . "or try 'perldoc $PROGRAM_NAME' "
              . "for complete documentation.";
   $descr = join("\n", $descr =~ m/(.{0,80})(?:\s+|$)/g)
      unless $ENV{DONT_BREAK_LINES};
   $descr =~ s/ +$//mg;
   return $descr;
}

sub usage_or_errors {
   my ( $self, $file, $return ) = @_;
   $file ||= $self->{file} || __FILE__;

   if ( !$self->{description} || !$self->{usage} ) {
      PTDEBUG && _d("Getting description and usage from SYNOPSIS in", $file);
      my %synop = $self->_parse_synopsis($file);
      $self->{description} ||= $synop{description};
      $self->{usage}       ||= $synop{usage};
      PTDEBUG && _d("Description:", $self->{description},
         "\nUsage:", $self->{usage});
   }

   if ( $self->{opts}->{help}->{got} ) {
      print $self->print_usage() or die "Cannot print usage: $OS_ERROR";
      exit 0 unless $return;
   }
   elsif ( scalar @{$self->{errors}} ) {
      print $self->print_errors() or die "Cannot print errors: $OS_ERROR";
      exit 1 unless $return;
   }

   return;
}

sub print_errors {
   my ( $self ) = @_;
   my $usage = $self->usage() . "\n";
   if ( (my @errors = @{$self->{errors}}) ) {
      $usage .= join("\n  * ", 'Errors in command-line arguments:', @errors)
              . "\n";
   }
   return $usage . "\n" . $self->descr();
}

sub print_usage {
   my ( $self ) = @_;
   die "Run get_opts() before print_usage()" unless $self->{got_opts};
   my @opts = values %{$self->{opts}};

   my $maxl = max(
      map {
         length($_->{long})               # option long name
         + ($_->{is_negatable} ? 4 : 0)   # "[no]" if opt is negatable
         + ($_->{type} ? 2 : 0)           # "=x" where x is the opt type
      }
      @opts);

   my $maxs = max(0,
      map {
         length($_)
         + ($self->{opts}->{$_}->{is_negatable} ? 4 : 0)
         + ($self->{opts}->{$_}->{type} ? 2 : 0)
      }
      values %{$self->{short_opts}});

   my $lcol = max($maxl, ($maxs + 3));
   my $rcol = 80 - $lcol - 6;
   my $rpad = ' ' x ( 80 - $rcol );

   $maxs = max($lcol - 3, $maxs);

   my $usage = $self->descr() . "\n" . $self->usage();

   my @groups = reverse sort grep { $_ ne 'default'; } keys %{$self->{groups}};
   push @groups, 'default';

   foreach my $group ( reverse @groups ) {
      $usage .= "\n".($group eq 'default' ? 'Options' : $group).":\n\n";
      foreach my $opt (
         sort { $a->{long} cmp $b->{long} }
         grep { $_->{group} eq $group }
         @opts )
      {
         my $long  = $opt->{is_negatable} ? "[no]$opt->{long}" : $opt->{long};
         my $short = $opt->{short};
         my $desc  = $opt->{desc};

         $long .= $opt->{type} ? "=$opt->{type}" : "";

         if ( $opt->{type} && $opt->{type} eq 'm' ) {
            my ($s) = $desc =~ m/\(suffix (.)\)/;
            $s    ||= 's';
            $desc =~ s/\s+\(suffix .\)//;
            $desc .= ".  Optional suffix s=seconds, m=minutes, h=hours, "
                   . "d=days; if no suffix, $s is used.";
         }
         $desc = join("\n$rpad", grep { $_ } $desc =~ m/(.{0,$rcol}(?!\W))(?:\s+|(?<=\W)|$)/g);
         $desc =~ s/ +$//mg;
         if ( $short ) {
            $usage .= sprintf("  --%-${maxs}s -%s  %s\n", $long, $short, $desc);
         }
         else {
            $usage .= sprintf("  --%-${lcol}s  %s\n", $long, $desc);
         }
      }
   }

   $usage .= "\nOption types: s=string, i=integer, f=float, h/H/a/A=comma-separated list, d=DSN, z=size, m=time\n";

   if ( (my @rules = @{$self->{rules}}) ) {
      $usage .= "\nRules:\n\n";
      $usage .= join("\n", map { "  $_" } @rules) . "\n";
   }
   if ( $self->{DSNParser} ) {
      $usage .= "\n" . $self->{DSNParser}->usage();
   }
   $usage .= "\nOptions and values after processing arguments:\n\n";
   foreach my $opt ( sort { $a->{long} cmp $b->{long} } @opts ) {
      my $val   = $opt->{value};
      my $type  = $opt->{type} || '';
      my $bool  = $opt->{spec} =~ m/^[\w-]+(?:\|[\w-])?!?$/;
      $val      = $bool              ? ( $val ? 'TRUE' : 'FALSE' )
                : !defined $val      ? '(No value)'
                : $type eq 'd'       ? $self->{DSNParser}->as_string($val)
                : $type =~ m/H|h/    ? join(',', sort keys %$val)
                : $type =~ m/A|a/    ? join(',', @$val)
                :                    $val;
      $usage .= sprintf("  --%-${lcol}s  %s\n", $opt->{long}, $val);
   }
   return $usage;
}

sub prompt_noecho {
   shift @_ if ref $_[0] eq __PACKAGE__;
   my ( $prompt ) = @_;
   local $OUTPUT_AUTOFLUSH = 1;
   print STDERR $prompt
      or die "Cannot print: $OS_ERROR";
   my $response;
   eval {
      require Term::ReadKey;
      Term::ReadKey::ReadMode('noecho');
      chomp($response = <STDIN>);
      Term::ReadKey::ReadMode('normal');
      print "\n"
         or die "Cannot print: $OS_ERROR";
   };
   if ( $EVAL_ERROR ) {
      die "Cannot read response; is Term::ReadKey installed? $EVAL_ERROR";
   }
   return $response;
}

sub _read_config_file {
   my ( $self, $filename ) = @_;
   open my $fh, "<", $filename or die "Cannot open $filename: $OS_ERROR\n";
   my @args;
   my $prefix = '--';
   my $parse  = 1;

   LINE:
   while ( my $line = <$fh> ) {
      chomp $line;
      next LINE if $line =~ m/^\s*(?:\#|\;|$)/;
      $line =~ s/\s+#.*$//g;
      $line =~ s/^\s+|\s+$//g;
      if ( $line eq '--' ) {
         $prefix = '';
         $parse  = 0;
         next LINE;
      }

      if (  $parse
            && !$self->has('version-check')
            && $line =~ /version-check/
      ) {
         next LINE;
      }

      if ( $parse
         && (my($opt, $arg) = $line =~ m/^\s*([^=\s]+?)(?:\s*=\s*(.*?)\s*)?$/)
      ) {
         push @args, grep { defined $_ } ("$prefix$opt", $arg);
      }
      elsif ( $line =~ m/./ ) {
         push @args, $line;
      }
      else {
         die "Syntax error in file $filename at line $INPUT_LINE_NUMBER";
      }
   }
   close $fh;
   return @args;
}

sub read_para_after {
   my ( $self, $file, $regex ) = @_;
   open my $fh, "<", $file or die "Can't open $file: $OS_ERROR";
   local $INPUT_RECORD_SEPARATOR = '';
   my $para;
   while ( $para = <$fh> ) {
      next unless $para =~ m/^=pod$/m;
      last;
   }
   while ( $para = <$fh> ) {
      next unless $para =~ m/$regex/;
      last;
   }
   $para = <$fh>;
   chomp($para);
   close $fh or die "Can't close $file: $OS_ERROR";
   return $para;
}

sub clone {
   my ( $self ) = @_;

   my %clone = map {
      my $hashref  = $self->{$_};
      my $val_copy = {};
      foreach my $key ( keys %$hashref ) {
         my $ref = ref $hashref->{$key};
         $val_copy->{$key} = !$ref           ? $hashref->{$key}
                           : $ref eq 'HASH'  ? { %{$hashref->{$key}} }
                           : $ref eq 'ARRAY' ? [ @{$hashref->{$key}} ]
                           : $hashref->{$key};
      }
      $_ => $val_copy;
   } qw(opts short_opts defaults);

   foreach my $scalar ( qw(got_opts) ) {
      $clone{$scalar} = $self->{$scalar};
   }

   return bless \%clone;
}

sub _parse_size {
   my ( $self, $opt, $val ) = @_;

   if ( lc($val || '') eq 'null' ) {
      PTDEBUG && _d('NULL size for', $opt->{long});
      $opt->{value} = 'null';
      return;
   }

   my %factor_for = (k => 1_024, M => 1_048_576, G => 1_073_741_824);
   my ($pre, $num, $factor) = $val =~ m/^([+-])?(\d+)([kMG])?$/;
   if ( defined $num ) {
      if ( $factor ) {
         $num *= $factor_for{$factor};
         PTDEBUG && _d('Setting option', $opt->{y},
            'to num', $num, '* factor', $factor);
      }
      $opt->{value} = ($pre || '') . $num;
   }
   else {
      $self->save_error("Invalid size for --$opt->{long}: $val");
   }
   return;
}

sub _parse_attribs {
   my ( $self, $option, $attribs ) = @_;
   my $types = $self->{types};
   return $option
      . ($attribs->{'short form'} ? '|' . $attribs->{'short form'}   : '' )
      . ($attribs->{'negatable'}  ? '!'                              : '' )
      . ($attribs->{'cumulative'} ? '+'                              : '' )
      . ($attribs->{'type'}       ? '=' . $types->{$attribs->{type}} : '' );
}

sub _parse_synopsis {
   my ( $self, $file ) = @_;
   $file ||= $self->{file} || __FILE__;
   PTDEBUG && _d("Parsing SYNOPSIS in", $file);

   local $INPUT_RECORD_SEPARATOR = '';  # read paragraphs
   open my $fh, "<", $file or die "Cannot open $file: $OS_ERROR";
   my $para;
   1 while defined($para = <$fh>) && $para !~ m/^=head1 SYNOPSIS/;
   die "$file does not contain a SYNOPSIS section" unless $para;
   my @synop;
   for ( 1..2 ) {  # 1 for the usage, 2 for the description
      my $para = <$fh>;
      push @synop, $para;
   }
   close $fh;
   PTDEBUG && _d("Raw SYNOPSIS text:", @synop);
   my ($usage, $desc) = @synop;
   die "The SYNOPSIS section in $file is not formatted properly"
      unless $usage && $desc;

   $usage =~ s/^\s*Usage:\s+(.+)/$1/;
   chomp $usage;

   $desc =~ s/\n/ /g;
   $desc =~ s/\s{2,}/ /g;
   $desc =~ s/\. ([A-Z][a-z])/.  $1/g;
   $desc =~ s/\s+$//;

   return (
      description => $desc,
      usage       => $usage,
   );
};

sub set_vars {
   my ($self, $file) = @_;
   $file ||= $self->{file} || __FILE__;

   my %user_vars;
   my $user_vars = $self->has('set-vars') ? $self->get('set-vars') : undef;
   if ( $user_vars ) {
      foreach my $var_val ( @$user_vars ) {
         my ($var, $val) = $var_val =~ m/([^\s=]+)=(\S+)/;
         die "Invalid --set-vars value: $var_val\n" unless $var && defined $val;
         $user_vars{$var} = {
            val     => $val,
            default => 0,
         };
      }
   }

   my %default_vars;
   my $default_vars = $self->read_para_after($file, qr/MAGIC_set_vars/);
   if ( $default_vars ) {
      %default_vars = map {
         my $var_val = $_;
         my ($var, $val) = $var_val =~ m/([^\s=]+)=(\S+)/;
         die "Invalid --set-vars value: $var_val\n" unless $var && defined $val;
         $var => {
            val     => $val,
            default => 1,
         };
      } split("\n", $default_vars);
   }

   my %vars = (
      %default_vars, # first the tool's defaults
      %user_vars,    # then the user's which overwrite the defaults
   );
   PTDEBUG && _d('--set-vars:', Dumper(\%vars));
   return \%vars;
}

sub _d {
   my ($package, undef, $line) = caller 0;
   @_ = map { (my $temp = $_) =~ s/\n/\n# /g; $temp; }
        map { defined $_ ? $_ : 'undef' }
        @_;
   print STDERR "# $package:$line $PID ", join(' ', @_), "\n";
}

if ( PTDEBUG ) {
   print STDERR '# ', $^X, ' ', $], "\n";
   if ( my $uname = `uname -a` ) {
      $uname =~ s/\s+/ /g;
      print STDERR "# $uname\n";
   }
   print STDERR '# Arguments: ',
      join(' ', map { my $a = "_[$_]_"; $a =~ s/\n/\n# /g; $a; } @ARGV), "\n";
}

1;
}
# ###########################################################################
# End OptionParser package
# ###########################################################################


# ###########################################################################
# Lmo::Utils package
# This package is a copy without comments from the original.  The original
# with comments and its test file can be found in the Bazaar repository at,
#   lib/Lmo/Utils.pm
#   t/lib/Lmo/Utils.t
# See https://launchpad.net/percona-toolkit for more information.
# ###########################################################################
{
package Lmo::Utils;

use strict;
use warnings qw( FATAL all );
require Exporter;
our (@ISA, @EXPORT, @EXPORT_OK);

BEGIN {
   @ISA = qw(Exporter);
   @EXPORT = @EXPORT_OK = qw(
      _install_coderef
      _unimport_coderefs
      _glob_for
      _stash_for
   );
}

{
   no strict 'refs';
   sub _glob_for {
      return \*{shift()}
   }

   sub _stash_for {
      return \%{ shift() . "::" };
   }
}

sub _install_coderef {
   my ($to, $code) = @_;

   return *{ _glob_for $to } = $code;
}

sub _unimport_coderefs {
   my ($target, @names) = @_;
   return unless @names;
   my $stash = _stash_for($target);
   foreach my $name (@names) {
      if ($stash->{$name} and defined(&{$stash->{$name}})) {
         delete $stash->{$name};
      }
   }
}

1;
}
# ###########################################################################
# End Lmo::Utils package
# ###########################################################################

# ###########################################################################
# Lmo::Meta package
# This package is a copy without comments from the original.  The original
# with comments and its test file can be found in the Bazaar repository at,
#   lib/Lmo/Meta.pm
#   t/lib/Lmo/Meta.t
# See https://launchpad.net/percona-toolkit for more information.
# ###########################################################################
{
package Lmo::Meta;
use strict;
use warnings qw( FATAL all );

my %metadata_for;

sub new {
   my $class = shift;
   return bless { @_ }, $class
}

sub metadata_for {
   my $self    = shift;
   my ($class) = @_;

   return $metadata_for{$class} ||= {};
}

sub class { shift->{class} }

sub attributes {
   my $self = shift;
   return keys %{$self->metadata_for($self->class)}
}

sub attributes_for_new {
   my $self = shift;
   my @attributes;

   my $class_metadata = $self->metadata_for($self->class);
   while ( my ($attr, $meta) = each %$class_metadata ) {
      if ( exists $meta->{init_arg} ) {
         push @attributes, $meta->{init_arg}
               if defined $meta->{init_arg};
      }
      else {
         push @attributes, $attr;
      }
   }
   return @attributes;
}

1;
}
# ###########################################################################
# End Lmo::Meta package
# ###########################################################################

# ###########################################################################
# Lmo::Object package
# This package is a copy without comments from the original.  The original
# with comments and its test file can be found in the Bazaar repository at,
#   lib/Lmo/Object.pm
#   t/lib/Lmo/Object.t
# See https://launchpad.net/percona-toolkit for more information.
# ###########################################################################
{
package Lmo::Object;

use strict;
use warnings qw( FATAL all );

use Carp ();
use Scalar::Util qw(blessed);

use Lmo::Meta;
use Lmo::Utils qw(_glob_for);

sub new {
   my $class = shift;
   my $args  = $class->BUILDARGS(@_);

   my $class_metadata = Lmo::Meta->metadata_for($class);

   my @args_to_delete;
   while ( my ($attr, $meta) = each %$class_metadata ) {
      next unless exists $meta->{init_arg};
      my $init_arg = $meta->{init_arg};

      if ( defined $init_arg ) {
         $args->{$attr} = delete $args->{$init_arg};
      }
      else {
         push @args_to_delete, $attr;
      }
   }

   delete $args->{$_} for @args_to_delete;

   for my $attribute ( keys %$args ) {
      if ( my $coerce = $class_metadata->{$attribute}{coerce} ) {
         $args->{$attribute} = $coerce->($args->{$attribute});
      }
      if ( my $isa_check = $class_metadata->{$attribute}{isa} ) {
         my ($check_name, $check_sub) = @$isa_check;
         $check_sub->($args->{$attribute});
      }
   }

   while ( my ($attribute, $meta) = each %$class_metadata ) {
      next unless $meta->{required};
      Carp::confess("Attribute ($attribute) is required for $class")
         if ! exists $args->{$attribute}
   }

   my $self = bless $args, $class;

   my @build_subs;
   my $linearized_isa = mro::get_linear_isa($class);

   for my $isa_class ( @$linearized_isa ) {
      unshift @build_subs, *{ _glob_for "${isa_class}::BUILD" }{CODE};
   }
   my @args = %$args;
   for my $sub (grep { defined($_) && exists &$_ } @build_subs) {
      $sub->( $self, @args);
   }
   return $self;
}

sub BUILDARGS {
   shift; # No need for the classname
   if ( @_ == 1 && ref($_[0]) ) {
      Carp::confess("Single parameters to new() must be a HASH ref, not $_[0]")
         unless ref($_[0]) eq ref({});
      return {%{$_[0]}} # We want a new reference, always
   }
   else {
      return { @_ };
   }
}

sub meta {
   my $class = shift;
   $class    = Scalar::Util::blessed($class) || $class;
   return Lmo::Meta->new(class => $class);
}

1;
}
# ###########################################################################
# End Lmo::Object package
# ###########################################################################

# ###########################################################################
# Lmo::Types package
# This package is a copy without comments from the original.  The original
# with comments and its test file can be found in the Bazaar repository at,
#   lib/Lmo/Types.pm
#   t/lib/Lmo/Types.t
# See https://launchpad.net/percona-toolkit for more information.
# ###########################################################################
{
package Lmo::Types;

use strict;
use warnings qw( FATAL all );

use Carp ();
use Scalar::Util qw(looks_like_number blessed);


our %TYPES = (
   Bool   => sub { !$_[0] || (defined $_[0] && looks_like_number($_[0]) && $_[0] == 1) },
   Num    => sub { defined $_[0] && looks_like_number($_[0]) },
   Int    => sub { defined $_[0] && looks_like_number($_[0]) && $_[0] == int($_[0]) },
   Str    => sub { defined $_[0] },
   Object => sub { defined $_[0] && blessed($_[0]) },
   FileHandle => sub { local $@; require IO::Handle; fileno($_[0]) && $_[0]->opened },

   map {
      my $type = /R/ ? $_ : uc $_;
      $_ . "Ref" => sub { ref $_[0] eq $type }
   } qw(Array Code Hash Regexp Glob Scalar)
);

sub check_type_constaints {
   my ($attribute, $type_check, $check_name, $val) = @_;
   ( ref($type_check) eq 'CODE'
      ? $type_check->($val)
      : (ref $val eq $type_check
         || ($val && $val eq $type_check)
         || (exists $TYPES{$type_check} && $TYPES{$type_check}->($val)))
   )
   || Carp::confess(
        qq<Attribute ($attribute) does not pass the type constraint because: >
      . qq<Validation failed for '$check_name' with value >
      . (defined $val ? Lmo::Dumper($val) : 'undef') )
}

sub _nested_constraints {
   my ($attribute, $aggregate_type, $type) = @_;

   my $inner_types;
   if ( $type =~ /\A(ArrayRef|Maybe)\[(.*)\]\z/ ) {
      $inner_types = _nested_constraints($1, $2);
   }
   else {
      $inner_types = $TYPES{$type};
   }

   if ( $aggregate_type eq 'ArrayRef' ) {
      return sub {
         my ($val) = @_;
         return unless ref($val) eq ref([]);

         if ($inner_types) {
            for my $value ( @{$val} ) {
               return unless $inner_types->($value)
            }
         }
         else {
            for my $value ( @{$val} ) {
               return unless $value && ($value eq $type
                        || (Scalar::Util::blessed($value) && $value->isa($type)));
            }
         }
         return 1;
      };
   }
   elsif ( $aggregate_type eq 'Maybe' ) {
      return sub {
         my ($value) = @_;
         return 1 if ! defined($value);
         if ($inner_types) {
            return unless $inner_types->($value)
         }
         else {
            return unless $value eq $type
                        || (Scalar::Util::blessed($value) && $value->isa($type));
         }
         return 1;
      }
   }
   else {
      Carp::confess("Nested aggregate types are only implemented for ArrayRefs and Maybe");
   }
}

1;
}
# ###########################################################################
# End Lmo::Types package
# ###########################################################################

# ###########################################################################
# Lmo package
# This package is a copy without comments from the original.  The original
# with comments and its test file can be found in the Bazaar repository at,
#   lib/Lmo.pm
#   t/lib/Lmo.t
# See https://launchpad.net/percona-toolkit for more information.
# ###########################################################################
{
BEGIN {
$INC{"Lmo.pm"} = __FILE__;
package Lmo;
our $VERSION = '0.30_Percona'; # Forked from 0.30 of Mo.


use strict;
use warnings qw( FATAL all );

use Carp ();
use Scalar::Util qw(looks_like_number blessed);

use Lmo::Meta;
use Lmo::Object;
use Lmo::Types;

use Lmo::Utils;

my %export_for;
sub import {
   warnings->import(qw(FATAL all));
   strict->import();

   my $caller     = scalar caller(); # Caller's package
   my %exports = (
      extends  => \&extends,
      has      => \&has,
      with     => \&with,
      override => \&override,
      confess  => \&Carp::confess,
   );

   $export_for{$caller} = \%exports;

   for my $keyword ( keys %exports ) {
      _install_coderef "${caller}::$keyword" => $exports{$keyword};
   }

   if ( !@{ *{ _glob_for "${caller}::ISA" }{ARRAY} || [] } ) {
      @_ = "Lmo::Object";
      goto *{ _glob_for "${caller}::extends" }{CODE};
   }
}

sub extends {
   my $caller = scalar caller();
   for my $class ( @_ ) {
      _load_module($class);
   }
   _set_package_isa($caller, @_);
   _set_inherited_metadata($caller);
}

sub _load_module {
   my ($class) = @_;

   (my $file = $class) =~ s{::|'}{/}g;
   $file .= '.pm';
   { local $@; eval { require "$file" } } # or warn $@;
   return;
}

sub with {
   my $package = scalar caller();
   require Role::Tiny;
   for my $role ( @_ ) {
      _load_module($role);
      _role_attribute_metadata($package, $role);
   }
   Role::Tiny->apply_roles_to_package($package, @_);
}

sub _role_attribute_metadata {
   my ($package, $role) = @_;

   my $package_meta = Lmo::Meta->metadata_for($package);
   my $role_meta    = Lmo::Meta->metadata_for($role);

   %$package_meta = (%$role_meta, %$package_meta);
}

sub has {
   my $names  = shift;
   my $caller = scalar caller();

   my $class_metadata = Lmo::Meta->metadata_for($caller);

   for my $attribute ( ref $names ? @$names : $names ) {
      my %args   = @_;
      my $method = ($args{is} || '') eq 'ro'
         ? sub {
            Carp::confess("Cannot assign a value to a read-only accessor at reader ${caller}::${attribute}")
               if $#_;
            return $_[0]{$attribute};
         }
         : sub {
            return $#_
                  ? $_[0]{$attribute} = $_[1]
                  : $_[0]{$attribute};
         };

      $class_metadata->{$attribute} = ();

      if ( my $type_check = $args{isa} ) {
         my $check_name = $type_check;

         if ( my ($aggregate_type, $inner_type) = $type_check =~ /\A(ArrayRef|Maybe)\[(.*)\]\z/ ) {
            $type_check = Lmo::Types::_nested_constraints($attribute, $aggregate_type, $inner_type);
         }

         my $check_sub = sub {
            my ($new_val) = @_;
            Lmo::Types::check_type_constaints($attribute, $type_check, $check_name, $new_val);
         };

         $class_metadata->{$attribute}{isa} = [$check_name, $check_sub];
         my $orig_method = $method;
         $method = sub {
            $check_sub->($_[1]) if $#_;
            goto &$orig_method;
         };
      }

      if ( my $builder = $args{builder} ) {
         my $original_method = $method;
         $method = sub {
               $#_
                  ? goto &$original_method
                  : ! exists $_[0]{$attribute}
                     ? $_[0]{$attribute} = $_[0]->$builder
                     : goto &$original_method
         };
      }

      if ( my $code = $args{default} ) {
         Carp::confess("${caller}::${attribute}'s default is $code, but should be a coderef")
               unless ref($code) eq 'CODE';
         my $original_method = $method;
         $method = sub {
               $#_
                  ? goto &$original_method
                  : ! exists $_[0]{$attribute}
                     ? $_[0]{$attribute} = $_[0]->$code
                     : goto &$original_method
         };
      }

      if ( my $role = $args{does} ) {
         my $original_method = $method;
         $method = sub {
            if ( $#_ ) {
               Carp::confess(qq<Attribute ($attribute) doesn't consume a '$role' role">)
                  unless Scalar::Util::blessed($_[1]) && eval { $_[1]->does($role) }
            }
            goto &$original_method
         };
      }

      if ( my $coercion = $args{coerce} ) {
         $class_metadata->{$attribute}{coerce} = $coercion;
         my $original_method = $method;
         $method = sub {
            if ( $#_ ) {
               return $original_method->($_[0], $coercion->($_[1]))
            }
            goto &$original_method;
         }
      }

      _install_coderef "${caller}::$attribute" => $method;

      if ( $args{required} ) {
         $class_metadata->{$attribute}{required} = 1;
      }

      if ($args{clearer}) {
         _install_coderef "${caller}::$args{clearer}"
            => sub { delete shift->{$attribute} }
      }

      if ($args{predicate}) {
         _install_coderef "${caller}::$args{predicate}"
            => sub { exists shift->{$attribute} }
      }

      if ($args{handles}) {
         _has_handles($caller, $attribute, \%args);
      }

      if (exists $args{init_arg}) {
         $class_metadata->{$attribute}{init_arg} = $args{init_arg};
      }
   }
}

sub _has_handles {
   my ($caller, $attribute, $args) = @_;
   my $handles = $args->{handles};

   my $ref = ref $handles;
   my $kv;
   if ( $ref eq ref [] ) {
         $kv = { map { $_,$_ } @{$handles} };
   }
   elsif ( $ref eq ref {} ) {
         $kv = $handles;
   }
   elsif ( $ref eq ref qr// ) {
         Carp::confess("Cannot delegate methods based on a Regexp without a type constraint (isa)")
            unless $args->{isa};
         my $target_class = $args->{isa};
         $kv = {
            map   { $_, $_     }
            grep  { $_ =~ $handles }
            grep  { !exists $Lmo::Object::{$_} && $target_class->can($_) }
            grep  { !$export_for{$target_class}->{$_} }
            keys %{ _stash_for $target_class }
         };
   }
   else {
         Carp::confess("handles for $ref not yet implemented");
   }

   while ( my ($method, $target) = each %{$kv} ) {
         my $name = _glob_for "${caller}::$method";
         Carp::confess("You cannot overwrite a locally defined method ($method) with a delegation")
            if defined &$name;

         my ($target, @curried_args) = ref($target) ? @$target : $target;
         *$name = sub {
            my $self        = shift;
            my $delegate_to = $self->$attribute();
            my $error = "Cannot delegate $method to $target because the value of $attribute";
            Carp::confess("$error is not defined") unless $delegate_to;
            Carp::confess("$error is not an object (got '$delegate_to')")
               unless Scalar::Util::blessed($delegate_to) || (!ref($delegate_to) && $delegate_to->can($target));
            return $delegate_to->$target(@curried_args, @_);
         }
   }
}

sub _set_package_isa {
   my ($package, @new_isa) = @_;
   my $package_isa  = \*{ _glob_for "${package}::ISA" };
   @{*$package_isa} = @new_isa;
}

sub _set_inherited_metadata {
   my $class = shift;
   my $class_metadata = Lmo::Meta->metadata_for($class);
   my $linearized_isa = mro::get_linear_isa($class);
   my %new_metadata;

   for my $isa_class (reverse @$linearized_isa) {
      my $isa_metadata = Lmo::Meta->metadata_for($isa_class);
      %new_metadata = (
         %new_metadata,
         %$isa_metadata,
      );
   }
   %$class_metadata = %new_metadata;
}

sub unimport {
   my $caller = scalar caller();
   my $target = caller;
  _unimport_coderefs($target, keys %{$export_for{$caller}});
}

sub Dumper {
   require Data::Dumper;
   local $Data::Dumper::Indent    = 0;
   local $Data::Dumper::Sortkeys  = 0;
   local $Data::Dumper::Quotekeys = 0;
   local $Data::Dumper::Terse     = 1;

   Data::Dumper::Dumper(@_)
}

BEGIN {
   if ($] >= 5.010) {
      { local $@; require mro; }
   }
   else {
      local $@;
      eval {
         require MRO::Compat;
      } or do {
         *mro::get_linear_isa = *mro::get_linear_isa_dfs = sub {
            no strict 'refs';

            my $classname = shift;

            my @lin = ($classname);
            my %stored;
            foreach my $parent (@{"$classname\::ISA"}) {
               my $plin = mro::get_linear_isa_dfs($parent);
               foreach (@$plin) {
                     next if exists $stored{$_};
                     push(@lin, $_);
                     $stored{$_} = 1;
               }
            }
            return \@lin;
         };
      }
   }
}

sub override {
   my ($methods, $code) = @_;
   my $caller          = scalar caller;

   for my $method ( ref($methods) ? @$methods : $methods ) {
      my $full_method     = "${caller}::${method}";
      *{_glob_for $full_method} = $code;
   }
}

}
1;
}
# ###########################################################################
# End Lmo package
# ###########################################################################

# ###########################################################################
# VersionParser package
# This package is a copy without comments from the original.  The original
# with comments and its test file can be found in the Bazaar repository at,
#   lib/VersionParser.pm
#   t/lib/VersionParser.t
# See https://launchpad.net/percona-toolkit for more information.
# ###########################################################################
{
package VersionParser;

use Lmo;
use Scalar::Util qw(blessed);
use English qw(-no_match_vars);
use constant PTDEBUG => $ENV{PTDEBUG} || 0;

use overload (
   '""'     => "version",
   '<=>'    => "cmp",
   'cmp'    => "cmp",
   fallback => 1,
);

use Carp ();

has major => (
    is       => 'ro',
    isa      => 'Int',
    required => 1,
);

has [qw( minor revision )] => (
    is  => 'ro',
    isa => 'Num',
);

has flavor => (
    is      => 'ro',
    isa     => 'Str',
    default => sub { 'Unknown' },
);

has innodb_version => (
    is      => 'ro',
    isa     => 'Str',
    default => sub { 'NO' },
);

sub series {
   my $self = shift;
   return $self->_join_version($self->major, $self->minor);
}

sub version {
   my $self = shift;
   return $self->_join_version($self->major, $self->minor, $self->revision);
}

sub is_in {
   my ($self, $target) = @_;

   return $self eq $target;
}

sub _join_version {
    my ($self, @parts) = @_;

    return join ".", map { my $c = $_; $c =~ s/^0\./0/; $c } grep defined, @parts;
}
sub _split_version {
   my ($self, $str) = @_;
   my @version_parts = map { s/^0(?=\d)/0./; $_ } $str =~ m/(\d+)/g;
   return @version_parts[0..2];
}

sub normalized_version {
   my ( $self ) = @_;
   my $result = sprintf('%d%02d%02d', map { $_ || 0 } $self->major,
                                                      $self->minor,
                                                      $self->revision);
   PTDEBUG && _d($self->version, 'normalizes to', $result);
   return $result;
}

sub comment {
   my ( $self, $cmd ) = @_;
   my $v = $self->normalized_version();

   return "/*!$v $cmd */"
}

my @methods = qw(major minor revision);
sub cmp {
   my ($left, $right) = @_;
   my $right_obj = (blessed($right) && $right->isa(ref($left)))
                   ? $right
                   : ref($left)->new($right);

   my $retval = 0;
   for my $m ( @methods ) {
      last unless defined($left->$m) && defined($right_obj->$m);
      $retval = $left->$m <=> $right_obj->$m;
      last if $retval;
   }
   return $retval;
}

sub BUILDARGS {
   my $self = shift;

   if ( @_ == 1 ) {
      my %args;
      if ( blessed($_[0]) && $_[0]->can("selectrow_hashref") ) {
         PTDEBUG && _d("VersionParser got a dbh, trying to get the version");
         my $dbh = $_[0];
         local $dbh->{FetchHashKeyName} = 'NAME_lc';
         my $query = eval {
            $dbh->selectall_arrayref(q/SHOW VARIABLES LIKE 'version%'/, { Slice => {} })
         };
         if ( $query ) {
            $query = { map { $_->{variable_name} => $_->{value} } @$query };
            @args{@methods} = $self->_split_version($query->{version});
            $args{flavor} = delete $query->{version_comment}
                  if $query->{version_comment};
         }
         elsif ( eval { ($query) = $dbh->selectrow_array(q/SELECT VERSION()/) } ) {
            @args{@methods} = $self->_split_version($query);
         }
         else {
            Carp::confess("Couldn't get the version from the dbh while "
                        . "creating a VersionParser object: $@");
         }
         $args{innodb_version} = eval { $self->_innodb_version($dbh) };
      }
      elsif ( !ref($_[0]) ) {
         @args{@methods} = $self->_split_version($_[0]);
      }

      for my $method (@methods) {
         delete $args{$method} unless defined $args{$method};
      }
      @_ = %args if %args;
   }

   return $self->SUPER::BUILDARGS(@_);
}

sub _innodb_version {
   my ( $self, $dbh ) = @_;
   return unless $dbh;
   my $innodb_version = "NO";

   my ($innodb) =
      grep { $_->{engine} =~ m/InnoDB/i }
      map  {
         my %hash;
         @hash{ map { lc $_ } keys %$_ } = values %$_;
         \%hash;
      }
      @{ $dbh->selectall_arrayref("SHOW ENGINES", {Slice=>{}}) };
   if ( $innodb ) {
      PTDEBUG && _d("InnoDB support:", $innodb->{support});
      if ( $innodb->{support} =~ m/YES|DEFAULT/i ) {
         my $vars = $dbh->selectrow_hashref(
            "SHOW VARIABLES LIKE 'innodb_version'");
         $innodb_version = !$vars ? "BUILTIN"
                         :          ($vars->{Value} || $vars->{value});
      }
      else {
         $innodb_version = $innodb->{support};  # probably DISABLED or NO
      }
   }

   PTDEBUG && _d("InnoDB version:", $innodb_version);
   return $innodb_version;
}

sub _d {
   my ($package, undef, $line) = caller 0;
   @_ = map { (my $temp = $_) =~ s/\n/\n# /g; $temp; }
        map { defined $_ ? $_ : 'undef' }
        @_;
   print STDERR "# $package:$line $PID ", join(' ', @_), "\n";
}

no Lmo;
1;
}
# ###########################################################################
# End VersionParser package
# ###########################################################################

# ###########################################################################
# DSNParser package
# This package is a copy without comments from the original.  The original
# with comments and its test file can be found in the Bazaar repository at,
#   lib/DSNParser.pm
#   t/lib/DSNParser.t
# See https://launchpad.net/percona-toolkit for more information.
# ###########################################################################
{
package DSNParser;

use strict;
use warnings FATAL => 'all';
use English qw(-no_match_vars);
use constant PTDEBUG => $ENV{PTDEBUG} || 0;

use Data::Dumper;
$Data::Dumper::Indent    = 0;
$Data::Dumper::Quotekeys = 0;

my $dsn_sep = qr/(?<!\\),/;

eval {
   require DBI;
};
my $have_dbi = $EVAL_ERROR ? 0 : 1;

sub new {
   my ( $class, %args ) = @_;
   foreach my $arg ( qw(opts) ) {
      die "I need a $arg argument" unless $args{$arg};
   }
   my $self = {
      opts => {}  # h, P, u, etc.  Should come from DSN OPTIONS section in POD.
   };
   foreach my $opt ( @{$args{opts}} ) {
      if ( !$opt->{key} || !$opt->{desc} ) {
         die "Invalid DSN option: ", Dumper($opt);
      }
      PTDEBUG && _d('DSN option:',
         join(', ',
            map { "$_=" . (defined $opt->{$_} ? ($opt->{$_} || '') : 'undef') }
               keys %$opt
         )
      );
      $self->{opts}->{$opt->{key}} = {
         dsn  => $opt->{dsn},
         desc => $opt->{desc},
         copy => $opt->{copy} || 0,
      };
   }
   return bless $self, $class;
}

sub prop {
   my ( $self, $prop, $value ) = @_;
   if ( @_ > 2 ) {
      PTDEBUG && _d('Setting', $prop, 'property');
      $self->{$prop} = $value;
   }
   return $self->{$prop};
}

sub parse {
   my ( $self, $dsn, $prev, $defaults ) = @_;
   if ( !$dsn ) {
      PTDEBUG && _d('No DSN to parse');
      return;
   }
   PTDEBUG && _d('Parsing', $dsn);
   $prev     ||= {};
   $defaults ||= {};
   my %given_props;
   my %final_props;
   my $opts = $self->{opts};

   foreach my $dsn_part ( split($dsn_sep, $dsn) ) {
      $dsn_part =~ s/\\,/,/g;
      if ( my ($prop_key, $prop_val) = $dsn_part =~  m/^(.)=(.*)$/ ) {
         $given_props{$prop_key} = $prop_val;
      }
      else {
         PTDEBUG && _d('Interpreting', $dsn_part, 'as h=', $dsn_part);
         $given_props{h} = $dsn_part;
      }
   }

   foreach my $key ( keys %$opts ) {
      PTDEBUG && _d('Finding value for', $key);
      $final_props{$key} = $given_props{$key};
      if ( !defined $final_props{$key}
           && defined $prev->{$key} && $opts->{$key}->{copy} )
      {
         $final_props{$key} = $prev->{$key};
         PTDEBUG && _d('Copying value for', $key, 'from previous DSN');
      }
      if ( !defined $final_props{$key} ) {
         $final_props{$key} = $defaults->{$key};
         PTDEBUG && _d('Copying value for', $key, 'from defaults');
      }
   }

   foreach my $key ( keys %given_props ) {
      die "Unknown DSN option '$key' in '$dsn'.  For more details, "
            . "please use the --help option, or try 'perldoc $PROGRAM_NAME' "
            . "for complete documentation."
         unless exists $opts->{$key};
   }
   if ( (my $required = $self->prop('required')) ) {
      foreach my $key ( keys %$required ) {
         die "Missing required DSN option '$key' in '$dsn'.  For more details, "
               . "please use the --help option, or try 'perldoc $PROGRAM_NAME' "
               . "for complete documentation."
            unless $final_props{$key};
      }
   }

   return \%final_props;
}

sub parse_options {
   my ( $self, $o ) = @_;
   die 'I need an OptionParser object' unless ref $o eq 'OptionParser';
   my $dsn_string
      = join(',',
          map  { "$_=".$o->get($_); }
          grep { $o->has($_) && $o->get($_) }
          keys %{$self->{opts}}
        );
   PTDEBUG && _d('DSN string made from options:', $dsn_string);
   return $self->parse($dsn_string);
}

sub as_string {
   my ( $self, $dsn, $props ) = @_;
   return $dsn unless ref $dsn;
   my @keys = $props ? @$props : sort keys %$dsn;
   return join(',',
      map  { "$_=" . ($_ eq 'p' ? '...' : $dsn->{$_}) }
      grep {
         exists $self->{opts}->{$_}
         && exists $dsn->{$_}
         && defined $dsn->{$_}
      } @keys);
}

sub usage {
   my ( $self ) = @_;
   my $usage
      = "DSN syntax is key=value[,key=value...]  Allowable DSN keys:\n\n"
      . "  KEY  COPY  MEANING\n"
      . "  ===  ====  =============================================\n";
   my %opts = %{$self->{opts}};
   foreach my $key ( sort keys %opts ) {
      $usage .= "  $key    "
             .  ($opts{$key}->{copy} ? 'yes   ' : 'no    ')
             .  ($opts{$key}->{desc} || '[No description]')
             . "\n";
   }
   $usage .= "\n  If the DSN is a bareword, the word is treated as the 'h' key.\n";
   return $usage;
}

sub get_cxn_params {
   my ( $self, $info ) = @_;
   my $dsn;
   my %opts = %{$self->{opts}};
   my $driver = $self->prop('dbidriver') || '';
   if ( $driver eq 'Pg' ) {
      $dsn = 'DBI:Pg:dbname=' . ( $info->{D} || '' ) . ';'
         . join(';', map  { "$opts{$_}->{dsn}=$info->{$_}" }
                     grep { defined $info->{$_} }
                     qw(h P));
   }
   else {
      $dsn = 'DBI:mysql:' . ( $info->{D} || '' ) . ';'
         . join(';', map  { "$opts{$_}->{dsn}=$info->{$_}" }
                     grep { defined $info->{$_} }
                     qw(F h P S A))
         . ';mysql_read_default_group=client'
         . ($info->{L} ? ';mysql_local_infile=1' : '');
   }
   PTDEBUG && _d($dsn);
   return ($dsn, $info->{u}, $info->{p});
}

sub fill_in_dsn {
   my ( $self, $dbh, $dsn ) = @_;
   my $vars = $dbh->selectall_hashref('SHOW VARIABLES', 'Variable_name');
   my ($user, $db) = $dbh->selectrow_array('SELECT USER(), DATABASE()');
   $user =~ s/@.*//;
   $dsn->{h} ||= $vars->{hostname}->{Value};
   $dsn->{S} ||= $vars->{'socket'}->{Value};
   $dsn->{P} ||= $vars->{port}->{Value};
   $dsn->{u} ||= $user;
   $dsn->{D} ||= $db;
}

sub get_dbh {
   my ( $self, $cxn_string, $user, $pass, $opts ) = @_;
   $opts ||= {};
   my $defaults = {
      AutoCommit         => 0,
      RaiseError         => 1,
      PrintError         => 0,
      ShowErrorStatement => 1,
      mysql_enable_utf8 => ($cxn_string =~ m/charset=utf8/i ? 1 : 0),
   };
   @{$defaults}{ keys %$opts } = values %$opts;
   if (delete $defaults->{L}) { # L for LOAD DATA LOCAL INFILE, our own extension
      $defaults->{mysql_local_infile} = 1;
   }

   if ( $opts->{mysql_use_result} ) {
      $defaults->{mysql_use_result} = 1;
   }

   if ( !$have_dbi ) {
      die "Cannot connect to MySQL because the Perl DBI module is not "
         . "installed or not found.  Run 'perl -MDBI' to see the directories "
         . "that Perl searches for DBI.  If DBI is not installed, try:\n"
         . "  Debian/Ubuntu  apt-get install libdbi-perl\n"
         . "  RHEL/CentOS    yum install perl-DBI\n"
         . "  OpenSolaris    pkg install pkg:/SUNWpmdbi\n";

   }

   my $dbh;
   my $tries = 2;
   while ( !$dbh && $tries-- ) {
      PTDEBUG && _d($cxn_string, ' ', $user, ' ', $pass,
         join(', ', map { "$_=>$defaults->{$_}" } keys %$defaults ));

      $dbh = eval { DBI->connect($cxn_string, $user, $pass, $defaults) };

      if ( !$dbh && $EVAL_ERROR ) {
         if ( $EVAL_ERROR =~ m/locate DBD\/mysql/i ) {
            die "Cannot connect to MySQL because the Perl DBD::mysql module is "
               . "not installed or not found.  Run 'perl -MDBD::mysql' to see "
               . "the directories that Perl searches for DBD::mysql.  If "
               . "DBD::mysql is not installed, try:\n"
               . "  Debian/Ubuntu  apt-get install libdbd-mysql-perl\n"
               . "  RHEL/CentOS    yum install perl-DBD-MySQL\n"
               . "  OpenSolaris    pgk install pkg:/SUNWapu13dbd-mysql\n";
         }
         elsif ( $EVAL_ERROR =~ m/not a compiled character set|character set utf8/ ) {
            PTDEBUG && _d('Going to try again without utf8 support');
            delete $defaults->{mysql_enable_utf8};
         }
         if ( !$tries ) {
            die $EVAL_ERROR;
         }
      }
   }

   if ( $cxn_string =~ m/mysql/i ) {
      my $sql;

      if ( my ($charset) = $cxn_string =~ m/charset=([\w]+)/ ) {
         $sql = qq{/*!40101 SET NAMES "$charset"*/};
         PTDEBUG && _d($dbh, $sql);
         eval { $dbh->do($sql) };
         if ( $EVAL_ERROR ) {
            die "Error setting NAMES to $charset: $EVAL_ERROR";
         }
         PTDEBUG && _d('Enabling charset for STDOUT');
         if ( $charset eq 'utf8' ) {
            binmode(STDOUT, ':utf8')
               or die "Can't binmode(STDOUT, ':utf8'): $OS_ERROR";
         }
         else {
            binmode(STDOUT) or die "Can't binmode(STDOUT): $OS_ERROR";
         }
      }

      if ( my $vars = $self->prop('set-vars') ) {
         $self->set_vars($dbh, $vars);
      }

      $sql = 'SELECT @@SQL_MODE';
      PTDEBUG && _d($dbh, $sql);
      my ($sql_mode) = eval { $dbh->selectrow_array($sql) };
      if ( $EVAL_ERROR ) {
         die "Error getting the current SQL_MODE: $EVAL_ERROR";
      }

      $sql = 'SET @@SQL_QUOTE_SHOW_CREATE = 1'
            . '/*!40101, @@SQL_MODE=\'NO_AUTO_VALUE_ON_ZERO'
            . ($sql_mode ? ",$sql_mode" : '')
            . '\'*/';
      PTDEBUG && _d($dbh, $sql);
      eval { $dbh->do($sql) };
      if ( $EVAL_ERROR ) {
         die "Error setting SQL_QUOTE_SHOW_CREATE, SQL_MODE"
           . ($sql_mode ? " and $sql_mode" : '')
           . ": $EVAL_ERROR";
      }
   }
   my ($mysql_version) = eval { $dbh->selectrow_array('SELECT VERSION()') };
   if ($EVAL_ERROR) {
       die "Cannot get MySQL version: $EVAL_ERROR";
   }

   my (undef, $character_set_server) = eval { $dbh->selectrow_array("SHOW VARIABLES LIKE 'character_set_server'") };
   if ($EVAL_ERROR) {
       die "Cannot get MySQL var character_set_server: $EVAL_ERROR";
   }

   if ($mysql_version =~ m/^(\d+)\.(\d)\.(\d+).*/) {
       if ($1 >= 8 && $character_set_server =~ m/^utf8/) {
           $dbh->{mysql_enable_utf8} = 1;
           my $msg = "MySQL version $mysql_version >= 8 and character_set_server = $character_set_server\n".
                     "Setting: SET NAMES $character_set_server";
           PTDEBUG && _d($msg);
           eval { $dbh->do("SET NAMES 'utf8mb4'") };
           if ($EVAL_ERROR) {
               die "Cannot SET NAMES $character_set_server: $EVAL_ERROR";
           }
       }
   }

   PTDEBUG && _d('DBH info: ',
      $dbh,
      Dumper($dbh->selectrow_hashref(
         'SELECT DATABASE(), CONNECTION_ID(), VERSION()/*!50038 , @@hostname*/')),
      'Connection info:',      $dbh->{mysql_hostinfo},
      'Character set info:',   Dumper($dbh->selectall_arrayref(
                     "SHOW VARIABLES LIKE 'character_set%'", { Slice => {}})),
      '$DBD::mysql::VERSION:', $DBD::mysql::VERSION,
      '$DBI::VERSION:',        $DBI::VERSION,
   );

   return $dbh;
}

sub get_hostname {
   my ( $self, $dbh ) = @_;
   if ( my ($host) = ($dbh->{mysql_hostinfo} || '') =~ m/^(\w+) via/ ) {
      return $host;
   }
   my ( $hostname, $one ) = $dbh->selectrow_array(
      'SELECT /*!50038 @@hostname, */ 1');
   return $hostname;
}

sub disconnect {
   my ( $self, $dbh ) = @_;
   PTDEBUG && $self->print_active_handles($dbh);
   $dbh->disconnect;
}

sub print_active_handles {
   my ( $self, $thing, $level ) = @_;
   $level ||= 0;
   printf("# Active %sh: %s %s %s\n", ($thing->{Type} || 'undef'), "\t" x $level,
      $thing, (($thing->{Type} || '') eq 'st' ? $thing->{Statement} || '' : ''))
      or die "Cannot print: $OS_ERROR";
   foreach my $handle ( grep {defined} @{ $thing->{ChildHandles} } ) {
      $self->print_active_handles( $handle, $level + 1 );
   }
}

sub copy {
   my ( $self, $dsn_1, $dsn_2, %args ) = @_;
   die 'I need a dsn_1 argument' unless $dsn_1;
   die 'I need a dsn_2 argument' unless $dsn_2;
   my %new_dsn = map {
      my $key = $_;
      my $val;
      if ( $args{overwrite} ) {
         $val = defined $dsn_1->{$key} ? $dsn_1->{$key} : $dsn_2->{$key};
      }
      else {
         $val = defined $dsn_2->{$key} ? $dsn_2->{$key} : $dsn_1->{$key};
      }
      $key => $val;
   } keys %{$self->{opts}};
   return \%new_dsn;
}

sub set_vars {
   my ($self, $dbh, $vars) = @_;

   return unless $vars;

   foreach my $var ( sort keys %$vars ) {
      my $val = $vars->{$var}->{val};

      (my $quoted_var = $var) =~ s/_/\\_/;
      my ($var_exists, $current_val);
      eval {
         ($var_exists, $current_val) = $dbh->selectrow_array(
            "SHOW VARIABLES LIKE '$quoted_var'");
      };
      my $e = $EVAL_ERROR;
      if ( $e ) {
         PTDEBUG && _d($e);
      }

      if ( $vars->{$var}->{default} && !$var_exists ) {
         PTDEBUG && _d('Not setting default var', $var,
            'because it does not exist');
         next;
      }

      if ( $current_val && $current_val eq $val ) {
         PTDEBUG && _d('Not setting var', $var, 'because its value',
            'is already', $val);
         next;
      }

      my $sql = "SET SESSION $var=$val";
      PTDEBUG && _d($dbh, $sql);
      eval { $dbh->do($sql) };
      if ( my $set_error = $EVAL_ERROR ) {
         chomp($set_error);
         $set_error =~ s/ at \S+ line \d+//;
         my $msg = "Error setting $var: $set_error";
         if ( $current_val ) {
            $msg .= "  The current value for $var is $current_val.  "
                  . "If the variable is read only (not dynamic), specify "
                  . "--set-vars $var=$current_val to avoid this warning, "
                  . "else manually set the variable and restart MySQL.";
         }
         warn $msg . "\n\n";
      }
   }

   return;
}

sub _d {
   my ($package, undef, $line) = caller 0;
   @_ = map { (my $temp = $_) =~ s/\n/\n# /g; $temp; }
        map { defined $_ ? $_ : 'undef' }
        @_;
   print STDERR "# $package:$line $PID ", join(' ', @_), "\n";
}

1;
}
# ###########################################################################
# End DSNParser package
# ###########################################################################

# ###########################################################################
# Daemon package
# This package is a copy without comments from the original.  The original
# with comments and its test file can be found in the Bazaar repository at,
#   lib/Daemon.pm
#   t/lib/Daemon.t
# See https://launchpad.net/percona-toolkit for more information.
# ###########################################################################
{
package Daemon;

use strict;
use warnings FATAL => 'all';
use English qw(-no_match_vars);

use constant PTDEBUG => $ENV{PTDEBUG} || 0;

use POSIX qw(setsid);
use Fcntl qw(:DEFAULT);

sub new {
   my ($class, %args) = @_;
   my $self = {
      log_file       => $args{log_file},
      pid_file       => $args{pid_file},
      daemonize      => $args{daemonize},
      force_log_file => $args{force_log_file},
      parent_exit    => $args{parent_exit},
      pid_file_owner => 0,
   };
   return bless $self, $class;
}

sub run {
   my ($self) = @_;

   my $daemonize      = $self->{daemonize};
   my $pid_file       = $self->{pid_file};
   my $log_file       = $self->{log_file};
   my $force_log_file = $self->{force_log_file};
   my $parent_exit    = $self->{parent_exit};

   PTDEBUG && _d('Starting daemon');

   if ( $pid_file ) {
      eval {
         $self->_make_pid_file(
            pid      => $PID,  # parent's pid
            pid_file => $pid_file,
         );
      };
      die "$EVAL_ERROR\n" if $EVAL_ERROR;
      if ( !$daemonize ) {
         $self->{pid_file_owner} = $PID;  # parent's pid
      }
   }

   if ( $daemonize ) {
      defined (my $child_pid = fork()) or die "Cannot fork: $OS_ERROR";
      if ( $child_pid ) {
         PTDEBUG && _d('Forked child', $child_pid);
         $parent_exit->($child_pid) if $parent_exit;
         exit 0;
      }

      POSIX::setsid() or die "Cannot start a new session: $OS_ERROR";
      chdir '/'       or die "Cannot chdir to /: $OS_ERROR";

      if ( $pid_file ) {
         $self->_update_pid_file(
            pid      => $PID,  # child's pid
            pid_file => $pid_file,
         );
         $self->{pid_file_owner} = $PID;
      }
   }

   if ( $daemonize || $force_log_file ) {
      PTDEBUG && _d('Redirecting STDIN to /dev/null');
      close STDIN;
      open  STDIN, '/dev/null'
         or die "Cannot reopen STDIN to /dev/null: $OS_ERROR";
      if ( $log_file ) {
         PTDEBUG && _d('Redirecting STDOUT and STDERR to', $log_file);
         close STDOUT;
         open  STDOUT, '>>', $log_file
            or die "Cannot open log file $log_file: $OS_ERROR";

         close STDERR;
         open  STDERR, ">&STDOUT"
            or die "Cannot dupe STDERR to STDOUT: $OS_ERROR";
      }
      else {
         if ( -t STDOUT ) {
            PTDEBUG && _d('No log file and STDOUT is a terminal;',
               'redirecting to /dev/null');
            close STDOUT;
            open  STDOUT, '>', '/dev/null'
               or die "Cannot reopen STDOUT to /dev/null: $OS_ERROR";
         }
         if ( -t STDERR ) {
            PTDEBUG && _d('No log file and STDERR is a terminal;',
               'redirecting to /dev/null');
            close STDERR;
            open  STDERR, '>', '/dev/null'
               or die "Cannot reopen STDERR to /dev/null: $OS_ERROR";
         }
      }

      $OUTPUT_AUTOFLUSH = 1;
   }

   PTDEBUG && _d('Daemon running');
   return;
}

sub _make_pid_file {
   my ($self, %args) = @_;
   my @required_args = qw(pid pid_file);
   foreach my $arg ( @required_args ) {
      die "I need a $arg argument" unless $args{$arg};
   };
   my $pid      = $args{pid};
   my $pid_file = $args{pid_file};

   eval {
      sysopen(PID_FH, $pid_file, O_RDWR|O_CREAT|O_EXCL) or die $OS_ERROR;
      print PID_FH $PID, "\n";
      close PID_FH;
   };
   if ( my $e = $EVAL_ERROR ) {
      if ( $e =~ m/file exists/i ) {
         my $old_pid = $self->_check_pid_file(
            pid_file => $pid_file,
            pid      => $PID,
         );
         if ( $old_pid ) {
            warn "Overwriting PID file $pid_file because PID $old_pid "
               . "is not running.\n";
         }
         $self->_update_pid_file(
            pid      => $PID,
            pid_file => $pid_file
         );
      }
      else {
         die "Error creating PID file $pid_file: $e\n";
      }
   }

   return;
}

sub _check_pid_file {
   my ($self, %args) = @_;
   my @required_args = qw(pid_file pid);
   foreach my $arg ( @required_args ) {
      die "I need a $arg argument" unless $args{$arg};
   };
   my $pid_file = $args{pid_file};
   my $pid      = $args{pid};

   PTDEBUG && _d('Checking if PID in', $pid_file, 'is running');

   if ( ! -f $pid_file ) {
      PTDEBUG && _d('PID file', $pid_file, 'does not exist');
      return;
   }

   open my $fh, '<', $pid_file
      or die "Error opening $pid_file: $OS_ERROR";
   my $existing_pid = do { local $/; <$fh> };
   chomp($existing_pid) if $existing_pid;
   close $fh
      or die "Error closing $pid_file: $OS_ERROR";

   if ( $existing_pid ) {
      if ( $existing_pid == $pid ) {
         warn "The current PID $pid already holds the PID file $pid_file\n";
         return;
      }
      else {
         PTDEBUG && _d('Checking if PID', $existing_pid, 'is running');
         my $pid_is_alive = kill 0, $existing_pid;
         if ( $pid_is_alive ) {
            die "PID file $pid_file exists and PID $existing_pid is running\n";
         }
      }
   }
   else {
      die "PID file $pid_file exists but it is empty.  Remove the file "
         . "if the process is no longer running.\n";
   }

   return $existing_pid;
}

sub _update_pid_file {
   my ($self, %args) = @_;
   my @required_args = qw(pid pid_file);
   foreach my $arg ( @required_args ) {
      die "I need a $arg argument" unless $args{$arg};
   };
   my $pid      = $args{pid};
   my $pid_file = $args{pid_file};

   open my $fh, '>', $pid_file
      or die "Cannot open $pid_file: $OS_ERROR";
   print { $fh } $pid, "\n"
      or die "Cannot print to $pid_file: $OS_ERROR";
   close $fh
      or warn "Cannot close $pid_file: $OS_ERROR";

   return;
}

sub remove_pid_file {
   my ($self, $pid_file) = @_;
   $pid_file ||= $self->{pid_file};
   if ( $pid_file && -f $pid_file ) {
      unlink $self->{pid_file}
         or warn "Cannot remove PID file $pid_file: $OS_ERROR";
      PTDEBUG && _d('Removed PID file');
   }
   else {
      PTDEBUG && _d('No PID to remove');
   }
   return;
}

sub DESTROY {
   my ($self) = @_;

   if ( $self->{pid_file_owner} == $PID ) {
      $self->remove_pid_file();
   }

   return;
}

sub _d {
   my ($package, undef, $line) = caller 0;
   @_ = map { (my $temp = $_) =~ s/\n/\n# /g; $temp; }
        map { defined $_ ? $_ : 'undef' }
        @_;
   print STDERR "# $package:$line $PID ", join(' ', @_), "\n";
}

1;
}
# ###########################################################################
# End Daemon package
# ###########################################################################

# ###########################################################################
# Quoter package
# This package is a copy without comments from the original.  The original
# with comments and its test file can be found in the Bazaar repository at,
#   lib/Quoter.pm
#   t/lib/Quoter.t
# See https://launchpad.net/percona-toolkit for more information.
# ###########################################################################
{
package Quoter;

use strict;
use warnings FATAL => 'all';
use English qw(-no_match_vars);
use constant PTDEBUG => $ENV{PTDEBUG} || 0;

use Data::Dumper;
$Data::Dumper::Indent    = 1;
$Data::Dumper::Sortkeys  = 1;
$Data::Dumper::Quotekeys = 0;

sub new {
   my ( $class, %args ) = @_;
   return bless {}, $class;
}

sub quote {
   my ( $self, @vals ) = @_;
   foreach my $val ( @vals ) {
      $val =~ s/`/``/g;
   }
   return join('.', map { '`' . $_ . '`' } @vals);
}

sub quote_val {
   my ( $self, $val, %args ) = @_;

   return 'NULL' unless defined $val;          # undef = NULL
   return "''" if $val eq '';                  # blank string = ''
   return $val if $val =~ m/^0x[0-9a-fA-F]+$/  # quote hex data
                  && !$args{is_char};          # unless is_char is true

   return $val if $args{is_float};

   $val =~ s/(['\\])/\\$1/g;
   return "'$val'";
}

sub split_unquote {
   my ( $self, $db_tbl, $default_db ) = @_;
   my ( $db, $tbl ) = split(/[.]/, $db_tbl);
   if ( !$tbl ) {
      $tbl = $db;
      $db  = $default_db;
   }
   for ($db, $tbl) {
      next unless $_;
      s/\A`//;
      s/`\z//;
      s/``/`/g;
   }

   return ($db, $tbl);
}

sub literal_like {
   my ( $self, $like ) = @_;
   return unless $like;
   $like =~ s/([%_])/\\$1/g;
   return "'$like'";
}

sub join_quote {
   my ( $self, $default_db, $db_tbl ) = @_;
   return unless $db_tbl;
   my ($db, $tbl) = split(/[.]/, $db_tbl);
   if ( !$tbl ) {
      $tbl = $db;
      $db  = $default_db;
   }
   $db  = "`$db`"  if $db  && $db  !~ m/^`/;
   $tbl = "`$tbl`" if $tbl && $tbl !~ m/^`/;
   return $db ? "$db.$tbl" : $tbl;
}

sub serialize_list {
   my ( $self, @args ) = @_;
   PTDEBUG && _d('Serializing', Dumper(\@args));
   return unless @args;

   my @parts;
   foreach my $arg  ( @args ) {
      if ( defined $arg ) {
         $arg =~ s/,/\\,/g;      # escape commas
         $arg =~ s/\\N/\\\\N/g;  # escape literal \N
         push @parts, $arg;
      }
      else {
         push @parts, '\N';
      }
   }

   my $string = join(',', @parts);
   PTDEBUG && _d('Serialized: <', $string, '>');
   return $string;
}

sub deserialize_list {
   my ( $self, $string ) = @_;
   PTDEBUG && _d('Deserializing <', $string, '>');
   die "Cannot deserialize an undefined string" unless defined $string;

   my @parts;
   foreach my $arg ( split(/(?<!\\),/, $string) ) {
      if ( $arg eq '\N' ) {
         $arg = undef;
      }
      else {
         $arg =~ s/\\,/,/g;
         $arg =~ s/\\\\N/\\N/g;
      }
      push @parts, $arg;
   }

   if ( !@parts ) {
      my $n_empty_strings = $string =~ tr/,//;
      $n_empty_strings++;
      PTDEBUG && _d($n_empty_strings, 'empty strings');
      map { push @parts, '' } 1..$n_empty_strings;
   }
   elsif ( $string =~ m/(?<!\\),$/ ) {
      PTDEBUG && _d('Last value is an empty string');
      push @parts, '';
   }

   PTDEBUG && _d('Deserialized', Dumper(\@parts));
   return @parts;
}

sub _d {
   my ($package, undef, $line) = caller 0;
   @_ = map { (my $temp = $_) =~ s/\n/\n# /g; $temp; }
        map { defined $_ ? $_ : 'undef' }
        @_;
   print STDERR "# $package:$line $PID ", join(' ', @_), "\n";
}

1;
}
# ###########################################################################
# End Quoter package
# ###########################################################################

# ###########################################################################
# TableNibbler package
# This package is a copy without comments from the original.  The original
# with comments and its test file can be found in the Bazaar repository at,
#   lib/TableNibbler.pm
#   t/lib/TableNibbler.t
# See https://launchpad.net/percona-toolkit for more information.
# ###########################################################################
{
package TableNibbler;

use strict;
use warnings FATAL => 'all';
use English qw(-no_match_vars);
use constant PTDEBUG => $ENV{PTDEBUG} || 0;

sub new {
   my ( $class, %args ) = @_;
   my @required_args = qw(TableParser Quoter);
   foreach my $arg ( @required_args ) {
      die "I need a $arg argument" unless $args{$arg};
   }
   my $self = { %args };
   return bless $self, $class;
}

sub generate_asc_stmt {
   my ( $self, %args ) = @_;
   my @required_args = qw(tbl_struct index);
   foreach my $arg ( @required_args ) {
      die "I need a $arg argument" unless defined $args{$arg};
   }
   my ($tbl_struct, $index) = @args{@required_args};
   my @cols = $args{cols} ? @{$args{cols}} : @{$tbl_struct->{cols}};
   my $q    = $self->{Quoter};

   die "Index '$index' does not exist in table"
      unless exists $tbl_struct->{keys}->{$index};
   PTDEBUG && _d('Will ascend index', $index);

   my @asc_cols = @{$tbl_struct->{keys}->{$index}->{cols}};
   if ( $args{asc_first} ) {
      PTDEBUG && _d('Ascending only first column');
      @asc_cols = $asc_cols[0];
   }
   elsif ( my $n = $args{n_index_cols} ) {
      $n = scalar @asc_cols if $n > @asc_cols;
      PTDEBUG && _d('Ascending only first', $n, 'columns');
      @asc_cols = @asc_cols[0..($n-1)];
   }
   PTDEBUG && _d('Will ascend columns', join(', ', @asc_cols));

   my @asc_slice;
   my %col_posn = do { my $i = 0; map { $_ => $i++ } @cols };
   foreach my $col ( @asc_cols ) {
      if ( !exists $col_posn{$col} ) {
         push @cols, $col;
         $col_posn{$col} = $#cols;
      }
      push @asc_slice, $col_posn{$col};
   }
   PTDEBUG && _d('Will ascend, in ordinal position:', join(', ', @asc_slice));

   my $asc_stmt = {
      cols  => \@cols,
      index => $index,
      where => '',
      slice => [],
      scols => [],
   };

   if ( @asc_slice ) {
      my $cmp_where;
      foreach my $cmp ( qw(< <= >= >) ) {
         $cmp_where = $self->generate_cmp_where(
            type        => $cmp,
            slice       => \@asc_slice,
            cols        => \@cols,
            quoter      => $q,
            is_nullable => $tbl_struct->{is_nullable},
            type_for    => $tbl_struct->{type_for},
         );
         $asc_stmt->{boundaries}->{$cmp} = $cmp_where->{where};
      }
      my $cmp = $args{asc_only} ? '>' : '>=';
      $asc_stmt->{where} = $asc_stmt->{boundaries}->{$cmp};
      $asc_stmt->{slice} = $cmp_where->{slice};
      $asc_stmt->{scols} = $cmp_where->{scols};
   }

   return $asc_stmt;
}

sub generate_cmp_where {
   my ( $self, %args ) = @_;
   foreach my $arg ( qw(type slice cols is_nullable) ) {
      die "I need a $arg arg" unless defined $args{$arg};
   }
   my @slice       = @{$args{slice}};
   my @cols        = @{$args{cols}};
   my $is_nullable = $args{is_nullable};
   my $type_for    = $args{type_for};
   my $type        = $args{type};
   my $q           = $self->{Quoter};

   (my $cmp = $type) =~ s/=//;

   my @r_slice;    # Resulting slice columns, by ordinal
   my @r_scols;    # Ditto, by name

   my @clauses;
   foreach my $i ( 0 .. $#slice ) {
      my @clause;

      foreach my $j ( 0 .. $i - 1 ) {
         my $ord = $slice[$j];
         my $col = $cols[$ord];
         my $quo = $q->quote($col);
         my $val = ($col && ($type_for->{$col} || '')) eq 'enum' ? "CAST(? AS UNSIGNED)" : "?";
         if ( $is_nullable->{$col} ) {
            push @clause, "(($val IS NULL AND $quo IS NULL) OR ($quo = $val))";
            push @r_slice, $ord, $ord;
            push @r_scols, $col, $col;
         }
         else {
            push @clause, "$quo = $val";
            push @r_slice, $ord;
            push @r_scols, $col;
         }
      }

      my $ord = $slice[$i];
      my $col = $cols[$ord];
      my $quo = $q->quote($col);
      my $end = $i == $#slice; # Last clause of the whole group.
      my $val = ($col && ($type_for->{$col} || '')) eq 'enum' ? "CAST(? AS UNSIGNED)" : "?";
      if ( $is_nullable->{$col} ) {
         if ( $type =~ m/=/ && $end ) {
            push @clause, "($val IS NULL OR $quo $type $val)";
         }
         elsif ( $type =~ m/>/ ) {
            push @clause, "($val IS NULL AND $quo IS NOT NULL) OR ($quo $cmp $val)";
         }
         else { # If $type =~ m/</ ) {
            push @clauses, "(($val IS NOT NULL AND $quo IS NULL) OR ($quo $cmp $val))";
         }
         push @r_slice, $ord, $ord;
         push @r_scols, $col, $col;
      }
      else {
         push @r_slice, $ord;
         push @r_scols, $col;
         push @clause, ($type =~ m/=/ && $end ? "$quo $type $val" : "$quo $cmp $val");
      }

      push @clauses, '(' . join(' AND ', @clause) . ')' if @clause;
   }
   my $result = '(' . join(' OR ', @clauses) . ')';
   my $where = {
      slice => \@r_slice,
      scols => \@r_scols,
      where => $result,
   };
   return $where;
}

sub generate_del_stmt {
   my ( $self, %args ) = @_;

   my $tbl  = $args{tbl_struct};
   my @cols = $args{cols} ? @{$args{cols}} : ();
   my $tp   = $self->{TableParser};
   my $q    = $self->{Quoter};

   my @del_cols;
   my @del_slice;

   my $index = $tp->find_best_index($tbl, $args{index});
   die "Cannot find an ascendable index in table" unless $index;

   if ( $index && $tbl->{keys}->{$index}->{is_unique}) {
      @del_cols = @{$tbl->{keys}->{$index}->{cols}};
   }
   else {
      @del_cols = @{$tbl->{cols}};
   }
   PTDEBUG && _d('Columns needed for DELETE:', join(', ', @del_cols));

   my %col_posn = do { my $i = 0; map { $_ => $i++ } @cols };
   foreach my $col ( @del_cols ) {
      if ( !exists $col_posn{$col} ) {
         push @cols, $col;
         $col_posn{$col} = $#cols;
      }
      push @del_slice, $col_posn{$col};
   }
   PTDEBUG && _d('Ordinals needed for DELETE:', join(', ', @del_slice));

   my $del_stmt = {
      cols  => \@cols,
      index => $index,
      where => '',
      slice => [],
      scols => [],
   };

   my @clauses;
   foreach my $i ( 0 .. $#del_slice ) {
      my $ord = $del_slice[$i];
      my $col = $cols[$ord];
      my $quo = $q->quote($col);
      if ( $tbl->{is_nullable}->{$col} ) {
         push @clauses, "((? IS NULL AND $quo IS NULL) OR ($quo = ?))";
         push @{$del_stmt->{slice}}, $ord, $ord;
         push @{$del_stmt->{scols}}, $col, $col;
      }
      else {
         push @clauses, "$quo = ?";
         push @{$del_stmt->{slice}}, $ord;
         push @{$del_stmt->{scols}}, $col;
      }
   }

   $del_stmt->{where} = '(' . join(' AND ', @clauses) . ')';

   return $del_stmt;
}

sub generate_ins_stmt {
   my ( $self, %args ) = @_;
   foreach my $arg ( qw(ins_tbl sel_cols) ) {
      die "I need a $arg argument" unless $args{$arg};
   }
   my $ins_tbl  = $args{ins_tbl};
   my @sel_cols = @{$args{sel_cols}};

   die "You didn't specify any SELECT columns" unless @sel_cols;

   my @ins_cols;
   my @ins_slice;
   for my $i ( 0..$#sel_cols ) {
      next unless $ins_tbl->{is_col}->{$sel_cols[$i]};
      push @ins_cols, $sel_cols[$i];
      push @ins_slice, $i;
   }

   return {
      cols  => \@ins_cols,
      slice => \@ins_slice,
   };
}

sub _d {
   my ($package, undef, $line) = caller 0;
   @_ = map { (my $temp = $_) =~ s/\n/\n# /g; $temp; }
        map { defined $_ ? $_ : 'undef' }
        @_;
   print STDERR "# $package:$line $PID ", join(' ', @_), "\n";
}

1;
}
# ###########################################################################
# End TableNibbler package
# ###########################################################################

# ###########################################################################
# TableParser package
# This package is a copy without comments from the original.  The original
# with comments and its test file can be found in the Bazaar repository at,
#   lib/TableParser.pm
#   t/lib/TableParser.t
# See https://launchpad.net/percona-toolkit for more information.
# ###########################################################################
{
package TableParser;

use strict;
use warnings FATAL => 'all';
use English qw(-no_match_vars);
use constant PTDEBUG => $ENV{PTDEBUG} || 0;

use Data::Dumper;
$Data::Dumper::Indent    = 1;
$Data::Dumper::Sortkeys  = 1;
$Data::Dumper::Quotekeys = 0;

local $EVAL_ERROR;
eval {
   require Quoter;
};

sub new {
   my ( $class, %args ) = @_;
   my $self = { %args };
   $self->{Quoter} ||= Quoter->new();
   return bless $self, $class;
}

sub Quoter { shift->{Quoter} }

sub get_create_table {
   my ( $self, $dbh, $db, $tbl ) = @_;
   die "I need a dbh parameter" unless $dbh;
   die "I need a db parameter"  unless $db;
   die "I need a tbl parameter" unless $tbl;
   my $q = $self->{Quoter};

   my $new_sql_mode
      = q{/*!40101 SET @OLD_SQL_MODE := @@SQL_MODE, }
      . q{@@SQL_MODE := '', }
      . q{@OLD_QUOTE := @@SQL_QUOTE_SHOW_CREATE, }
      . q{@@SQL_QUOTE_SHOW_CREATE := 1 */};

   my $old_sql_mode
      = q{/*!40101 SET @@SQL_MODE := @OLD_SQL_MODE, }
      . q{@@SQL_QUOTE_SHOW_CREATE := @OLD_QUOTE */};

   PTDEBUG && _d($new_sql_mode);
   eval { $dbh->do($new_sql_mode); };
   PTDEBUG && $EVAL_ERROR && _d($EVAL_ERROR);

   my $use_sql = 'USE ' . $q->quote($db);
   PTDEBUG && _d($dbh, $use_sql);
   $dbh->do($use_sql);

   my $show_sql = "SHOW CREATE TABLE " . $q->quote($db, $tbl);
   PTDEBUG && _d($show_sql);
   my $href;
   eval { $href = $dbh->selectrow_hashref($show_sql); };
   if ( my $e = $EVAL_ERROR ) {
      PTDEBUG && _d($old_sql_mode);
      $dbh->do($old_sql_mode);

      die $e;
   }

   PTDEBUG && _d($old_sql_mode);
   $dbh->do($old_sql_mode);

   my ($key) = grep { m/create (?:table|view)/i } keys %$href;
   if ( !$key ) {
      die "Error: no 'Create Table' or 'Create View' in result set from "
         . "$show_sql: " . Dumper($href);
   }

   return $href->{$key};
}

sub parse {
   my ( $self, $ddl, $opts ) = @_;
   return unless $ddl;

   if ( $ddl =~ m/CREATE (?:TEMPORARY )?TABLE "/ ) {
      $ddl = $self->ansi_to_legacy($ddl);
   }
   elsif ( $ddl !~ m/CREATE (?:TEMPORARY )?TABLE `/ ) {
      die "TableParser doesn't handle CREATE TABLE without quoting.";
   }

   my ($name)     = $ddl =~ m/CREATE (?:TEMPORARY )?TABLE\s+(`.+?`)/;
   (undef, $name) = $self->{Quoter}->split_unquote($name) if $name;

   $ddl =~ s/(`[^`\n]+`)/\L$1/gm;

   my $engine = $self->get_engine($ddl);

   my @defs   = $ddl =~ m/^(\s+`.*?),?$/gm;
   my @cols   = map { $_ =~ m/`([^`]+)`/ } @defs;
   PTDEBUG && _d('Table cols:', join(', ', map { "`$_`" } @cols));

   my %def_for;
   @def_for{@cols} = @defs;

   my (@nums, @null, @non_generated);
   my (%type_for, %is_nullable, %is_numeric, %is_autoinc, %is_generated);
   foreach my $col ( @cols ) {
      my $def = $def_for{$col};

      $def =~ s/``//g;

      my ( $type ) = $def =~ m/`[^`]+`\s([a-z]+)/;
      die "Can't determine column type for $def" unless $type;
      $type_for{$col} = $type;
      if ( $type =~ m/(?:(?:tiny|big|medium|small)?int|float|double|decimal|year)/ ) {
         push @nums, $col;
         $is_numeric{$col} = 1;
      }
      if ( $def !~ m/NOT NULL/ ) {
         push @null, $col;
         $is_nullable{$col} = 1;
      }
      if ( remove_quoted_text($def) =~ m/\WGENERATED\W/i ) {
          $is_generated{$col} = 1;
      } else {
          push @non_generated, $col;
      }
      $is_autoinc{$col} = $def =~ m/AUTO_INCREMENT/i ? 1 : 0;
   }

   my ($keys, $clustered_key) = $self->get_keys($ddl, $opts, \%is_nullable);

   my ($charset) = $ddl =~ m/DEFAULT CHARSET=(\w+)/;

   return {
      name               => $name,
      cols               => \@cols,
      col_posn           => { map { $cols[$_] => $_ } 0..$#cols },
      is_col             => { map { $_ => 1 } @non_generated },
      null_cols          => \@null,
      is_nullable        => \%is_nullable,
      non_generated_cols => \@non_generated,
      is_autoinc         => \%is_autoinc,
      is_generated       => \%is_generated,
      clustered_key      => $clustered_key,
      keys               => $keys,
      defs               => \%def_for,
      numeric_cols       => \@nums,
      is_numeric         => \%is_numeric,
      engine             => $engine,
      type_for           => \%type_for,
      charset            => $charset,
   };
}

sub remove_quoted_text {
   my ($string) = @_;
   $string =~ s/\\['"]//g;
   $string =~ s/`[^`]*?`//g;
   $string =~ s/"[^"]*?"//g;
   $string =~ s/'[^']*?'//g;
   return $string;
}

sub sort_indexes {
   my ( $self, $tbl ) = @_;

   my @indexes
      = sort {
         (($a ne 'PRIMARY') <=> ($b ne 'PRIMARY'))
         || ( !$tbl->{keys}->{$a}->{is_unique} <=> !$tbl->{keys}->{$b}->{is_unique} )
         || ( $tbl->{keys}->{$a}->{is_nullable} <=> $tbl->{keys}->{$b}->{is_nullable} )
         || ( scalar(@{$tbl->{keys}->{$a}->{cols}}) <=> scalar(@{$tbl->{keys}->{$b}->{cols}}) )
      }
      grep {
         $tbl->{keys}->{$_}->{type} eq 'BTREE'
      }
      sort keys %{$tbl->{keys}};

   PTDEBUG && _d('Indexes sorted best-first:', join(', ', @indexes));
   return @indexes;
}

sub find_best_index {
   my ( $self, $tbl, $index ) = @_;
   my $best;
   if ( $index ) {
      ($best) = grep { uc $_ eq uc $index } keys %{$tbl->{keys}};
   }
   if ( !$best ) {
      if ( $index ) {
         die "Index '$index' does not exist in table";
      }
      else {
         ($best) = $self->sort_indexes($tbl);
      }
   }
   PTDEBUG && _d('Best index found is', $best);
   return $best;
}

sub find_possible_keys {
   my ( $self, $dbh, $database, $table, $quoter, $where ) = @_;
   return () unless $where;
   my $sql = 'EXPLAIN SELECT * FROM ' . $quoter->quote($database, $table)
      . ' WHERE ' . $where;
   PTDEBUG && _d($sql);
   my $expl = $dbh->selectrow_hashref($sql);
   $expl = { map { lc($_) => $expl->{$_} } keys %$expl };
   if ( $expl->{possible_keys} ) {
      PTDEBUG && _d('possible_keys =', $expl->{possible_keys});
      my @candidates = split(',', $expl->{possible_keys});
      my %possible   = map { $_ => 1 } @candidates;
      if ( $expl->{key} ) {
         PTDEBUG && _d('MySQL chose', $expl->{key});
         unshift @candidates, grep { $possible{$_} } split(',', $expl->{key});
         PTDEBUG && _d('Before deduping:', join(', ', @candidates));
         my %seen;
         @candidates = grep { !$seen{$_}++ } @candidates;
      }
      PTDEBUG && _d('Final list:', join(', ', @candidates));
      return @candidates;
   }
   else {
      PTDEBUG && _d('No keys in possible_keys');
      return ();
   }
}

sub check_table {
   my ( $self, %args ) = @_;
   my @required_args = qw(dbh db tbl);
   foreach my $arg ( @required_args ) {
      die "I need a $arg argument" unless $args{$arg};
   }
   my ($dbh, $db, $tbl) = @args{@required_args};
   my $q      = $self->{Quoter} || 'Quoter';
   my $db_tbl = $q->quote($db, $tbl);
   PTDEBUG && _d('Checking', $db_tbl);

   $self->{check_table_error} = undef;

   my $sql = "SHOW TABLES FROM " . $q->quote($db)
           . ' LIKE ' . $q->literal_like($tbl);
   PTDEBUG && _d($sql);
   my $row;
   eval {
      $row = $dbh->selectrow_arrayref($sql);
   };
   if ( my $e = $EVAL_ERROR ) {
      PTDEBUG && _d($e);
      $self->{check_table_error} = $e;
      return 0;
   }
   if ( !$row->[0] || $row->[0] ne $tbl ) {
      PTDEBUG && _d('Table does not exist');
      return 0;
   }

   PTDEBUG && _d('Table', $db, $tbl, 'exists');
   return 1;

}

sub get_engine {
   my ( $self, $ddl, $opts ) = @_;
   my ( $engine ) = $ddl =~ m/\).*?(?:ENGINE|TYPE)=(\w+)/;
   PTDEBUG && _d('Storage engine:', $engine);
   return $engine || undef;
}

sub get_keys {
   my ( $self, $ddl, $opts, $is_nullable ) = @_;
   my $engine        = $self->get_engine($ddl);
   my $keys          = {};
   my $clustered_key = undef;

   KEY:
   foreach my $key ( $ddl =~ m/^  ((?:[A-Z]+ )?KEY .*)$/gm ) {

      next KEY if $key =~ m/FOREIGN/;

      my $key_ddl = $key;
      PTDEBUG && _d('Parsed key:', $key_ddl);

      if ( !$engine || $engine !~ m/MEMORY|HEAP/ ) {
         $key =~ s/USING HASH/USING BTREE/;
      }

      my ( $type, $cols ) = $key =~ m/(?:USING (\w+))? \((.+)\)/;
      my ( $special ) = $key =~ m/(FULLTEXT|SPATIAL)/;
      $type = $type || $special || 'BTREE';
      my ($name) = $key =~ m/(PRIMARY|`[^`]*`)/;
      my $unique = $key =~ m/PRIMARY|UNIQUE/ ? 1 : 0;
      my @cols;
      my @col_prefixes;
      foreach my $col_def ( $cols =~ m/`[^`]+`(?:\(\d+\))?/g ) {
         my ($name, $prefix) = $col_def =~ m/`([^`]+)`(?:\((\d+)\))?/;
         push @cols, $name;
         push @col_prefixes, $prefix;
      }
      $name =~ s/`//g;

      PTDEBUG && _d( $name, 'key cols:', join(', ', map { "`$_`" } @cols));

      $keys->{$name} = {
         name         => $name,
         type         => $type,
         colnames     => $cols,
         cols         => \@cols,
         col_prefixes => \@col_prefixes,
         is_unique    => $unique,
         is_nullable  => scalar(grep { $is_nullable->{$_} } @cols),
         is_col       => { map { $_ => 1 } @cols },
         ddl          => $key_ddl,
      };

      if ( ($engine || '') =~ m/InnoDB/i && !$clustered_key ) {
         my $this_key = $keys->{$name};
         if ( $this_key->{name} eq 'PRIMARY' ) {
            $clustered_key = 'PRIMARY';
         }
         elsif ( $this_key->{is_unique} && !$this_key->{is_nullable} ) {
            $clustered_key = $this_key->{name};
         }
         PTDEBUG && $clustered_key && _d('This key is the clustered key');
      }
   }

   return $keys, $clustered_key;
}

sub get_fks {
   my ( $self, $ddl, $opts ) = @_;
   my $q   = $self->{Quoter};
   my $fks = {};

   foreach my $fk (
      $ddl =~ m/CONSTRAINT .* FOREIGN KEY .* REFERENCES [^\)]*\)/mg )
   {
      my ( $name ) = $fk =~ m/CONSTRAINT `(.*?)`/;
      my ( $cols ) = $fk =~ m/FOREIGN KEY \(([^\)]+)\)/;
      my ( $parent, $parent_cols ) = $fk =~ m/REFERENCES (\S+) \(([^\)]+)\)/;

      my ($db, $tbl) = $q->split_unquote($parent, $opts->{database});
      my %parent_tbl = (tbl => $tbl);
      $parent_tbl{db} = $db if $db;

      if ( $parent !~ m/\./ && $opts->{database} ) {
         $parent = $q->quote($opts->{database}) . ".$parent";
      }

      $fks->{$name} = {
         name           => $name,
         colnames       => $cols,
         cols           => [ map { s/[ `]+//g; $_; } split(',', $cols) ],
         parent_tbl     => \%parent_tbl,
         parent_tblname => $parent,
         parent_cols    => [ map { s/[ `]+//g; $_; } split(',', $parent_cols) ],
         parent_colnames=> $parent_cols,
         ddl            => $fk,
      };
   }

   return $fks;
}

sub remove_auto_increment {
   my ( $self, $ddl ) = @_;
   $ddl =~ s/(^\).*?) AUTO_INCREMENT=\d+\b/$1/m;
   return $ddl;
}

sub get_table_status {
   my ( $self, $dbh, $db, $like ) = @_;
   my $q = $self->{Quoter};
   my $sql = "SHOW TABLE STATUS FROM " . $q->quote($db);
   my @params;
   if ( $like ) {
      $sql .= ' LIKE ?';
      push @params, $like;
   }
   PTDEBUG && _d($sql, @params);
   my $sth = $dbh->prepare($sql);
   eval { $sth->execute(@params); };
   if ($EVAL_ERROR) {
      PTDEBUG && _d($EVAL_ERROR);
      return;
   }
   my @tables = @{$sth->fetchall_arrayref({})};
   @tables = map {
      my %tbl; # Make a copy with lowercased keys
      @tbl{ map { lc $_ } keys %$_ } = values %$_;
      $tbl{engine} ||= $tbl{type} || $tbl{comment};
      delete $tbl{type};
      \%tbl;
   } @tables;
   return @tables;
}

my $ansi_quote_re = qr/" [^"]* (?: "" [^"]* )* (?<=.) "/ismx;
sub ansi_to_legacy {
   my ($self, $ddl) = @_;
   $ddl =~ s/($ansi_quote_re)/ansi_quote_replace($1)/ge;
   return $ddl;
}

sub ansi_quote_replace {
   my ($val) = @_;
   $val =~ s/^"|"$//g;
   $val =~ s/`/``/g;
   $val =~ s/""/"/g;
   return "`$val`";
}

sub _d {
   my ($package, undef, $line) = caller 0;
   @_ = map { (my $temp = $_) =~ s/\n/\n# /g; $temp; }
        map { defined $_ ? $_ : 'undef' }
        @_;
   print STDERR "# $package:$line $PID ", join(' ', @_), "\n";
}

1;
}
# ###########################################################################
# End TableParser package
# ###########################################################################

# ###########################################################################
# Progress package
# This package is a copy without comments from the original.  The original
# with comments and its test file can be found in the Bazaar repository at,
#   lib/Progress.pm
#   t/lib/Progress.t
# See https://launchpad.net/percona-toolkit for more information.
# ###########################################################################
{
package Progress;

use strict;
use warnings FATAL => 'all';
use English qw(-no_match_vars);
use constant PTDEBUG => $ENV{PTDEBUG} || 0;

sub new {
   my ( $class, %args ) = @_;
   foreach my $arg (qw(jobsize)) {
      die "I need a $arg argument" unless defined $args{$arg};
   }
   if ( (!$args{report} || !$args{interval}) ) {
      if ( $args{spec} && @{$args{spec}} == 2 ) {
         @args{qw(report interval)} = @{$args{spec}};
      }
      else {
         die "I need either report and interval arguments, or a spec";
      }
   }

   my $name  = $args{name} || "Progress";
   $args{start} ||= time();
   my $self;
   $self = {
      last_reported => $args{start},
      fraction      => 0,       # How complete the job is
      callback      => sub {
         my ($fraction, $elapsed, $remaining) = @_;
         printf STDERR "$name: %3d%% %s remain\n",
            $fraction * 100,
            Transformers::secs_to_time($remaining);
      },
      %args,
   };
   return bless $self, $class;
}

sub validate_spec {
   shift @_ if $_[0] eq 'Progress'; # Permit calling as Progress-> or Progress::
   my ( $spec ) = @_;
   if ( @$spec != 2 ) {
      die "spec array requires a two-part argument\n";
   }
   if ( $spec->[0] !~ m/^(?:percentage|time|iterations)$/ ) {
      die "spec array's first element must be one of "
        . "percentage,time,iterations\n";
   }
   if ( $spec->[1] !~ m/^\d+$/ ) {
      die "spec array's second element must be an integer\n";
   }
}

sub set_callback {
   my ( $self, $callback ) = @_;
   $self->{callback} = $callback;
}

sub start {
   my ( $self, $start ) = @_;
   $self->{start} = $self->{last_reported} = $start || time();
   $self->{first_report} = 0;
}

sub update {
   my ( $self, $callback, %args ) = @_;
   my $jobsize   = $self->{jobsize};
   my $now    ||= $args{now} || time;

   $self->{iterations}++; # How many updates have happened;

   if ( !$self->{first_report} && $args{first_report} ) {
      $args{first_report}->();
      $self->{first_report} = 1;
   }

   if ( $self->{report} eq 'time'
         && $self->{interval} > $now - $self->{last_reported}
   ) {
      return;
   }
   elsif ( $self->{report} eq 'iterations'
         && ($self->{iterations} - 1) % $self->{interval} > 0
   ) {
      return;
   }
   $self->{last_reported} = $now;

   my $completed = $callback->();
   $self->{updates}++; # How many times we have run the update callback

   return if $completed > $jobsize;

   my $fraction = $completed > 0 ? $completed / $jobsize : 0;

   if ( $self->{report} eq 'percentage'
         && $self->fraction_modulo($self->{fraction})
            >= $self->fraction_modulo($fraction)
   ) {
      $self->{fraction} = $fraction;
      return;
   }
   $self->{fraction} = $fraction;

   my $elapsed   = $now - $self->{start};
   my $remaining = 0;
   my $eta       = $now;
   if ( $completed > 0 && $completed <= $jobsize && $elapsed > 0 ) {
      my $rate = $completed / $elapsed;
      if ( $rate > 0 ) {
         $remaining = ($jobsize - $completed) / $rate;
         $eta       = $now + int($remaining);
      }
   }
   $self->{callback}->($fraction, $elapsed, $remaining, $eta, $completed);
}

sub fraction_modulo {
   my ( $self, $num ) = @_;
   $num *= 100; # Convert from fraction to percentage
   return sprintf('%d',
      sprintf('%d', $num / $self->{interval}) * $self->{interval});
}

sub _d {
   my ($package, undef, $line) = caller 0;
   @_ = map { (my $temp = $_) =~ s/\n/\n# /g; $temp; }
        map { defined $_ ? $_ : 'undef' }
        @_;
   print STDERR "# $package:$line $PID ", join(' ', @_), "\n";
}

1;
}
# ###########################################################################
# End Progress package
# ###########################################################################

# ###########################################################################
# Retry package
# This package is a copy without comments from the original.  The original
# with comments and its test file can be found in the Bazaar repository at,
#   lib/Retry.pm
#   t/lib/Retry.t
# See https://launchpad.net/percona-toolkit for more information.
# ###########################################################################
{
package Retry;

use strict;
use warnings FATAL => 'all';
use English qw(-no_match_vars);
use constant PTDEBUG => $ENV{PTDEBUG} || 0;

use Time::HiRes qw(sleep);

sub new {
   my ( $class, %args ) = @_;
   my $self = {
      %args,
   };
   return bless $self, $class;
}

sub retry {
   my ( $self, %args ) = @_;
   my @required_args = qw(try fail final_fail);
   foreach my $arg ( @required_args ) {
      die "I need a $arg argument" unless $args{$arg};
   };
   my ($try, $fail, $final_fail) = @args{@required_args};
   my $wait  = $args{wait}  || sub { sleep 1; };
   my $tries = $args{tries} || 3;

   my $last_error;
   my $tryno = 0;
   TRY:
   while ( ++$tryno <= $tries ) {
      PTDEBUG && _d("Try", $tryno, "of", $tries);
      my $result;
      eval {
         $result = $try->(tryno=>$tryno);
      };
      if ( $EVAL_ERROR ) {
         PTDEBUG && _d("Try code failed:", $EVAL_ERROR);
         $last_error = $EVAL_ERROR;

         if ( $tryno < $tries ) {   # more retries
            my $retry = $fail->(tryno=>$tryno, error=>$last_error);
            last TRY unless $retry;
            PTDEBUG && _d("Calling wait code");
            $wait->(tryno=>$tryno);
         }
      }
      else {
         PTDEBUG && _d("Try code succeeded");
         return $result;
      }
   }

   PTDEBUG && _d('Try code did not succeed');
   return $final_fail->(error=>$last_error);
}

sub _d {
   my ($package, undef, $line) = caller 0;
   @_ = map { (my $temp = $_) =~ s/\n/\n# /g; $temp; }
        map { defined $_ ? $_ : 'undef' }
        @_;
   print STDERR "# $package:$line $PID ", join(' ', @_), "\n";
}

1;
}
# ###########################################################################
# End Retry package
# ###########################################################################

# ###########################################################################
# Cxn package
# This package is a copy without comments from the original.  The original
# with comments and its test file can be found in the Bazaar repository at,
#   lib/Cxn.pm
#   t/lib/Cxn.t
# See https://launchpad.net/percona-toolkit for more information.
# ###########################################################################
{
package Cxn;

use strict;
use warnings FATAL => 'all';
use English qw(-no_match_vars);
use Scalar::Util qw(blessed);
use constant {
   PTDEBUG => $ENV{PTDEBUG} || 0,
   PERCONA_TOOLKIT_TEST_USE_DSN_NAMES => $ENV{PERCONA_TOOLKIT_TEST_USE_DSN_NAMES} || 0,
};

sub new {
   my ( $class, %args ) = @_;
   my @required_args = qw(DSNParser OptionParser);
   foreach my $arg ( @required_args ) {
      die "I need a $arg argument" unless $args{$arg};
   };
   my ($dp, $o) = @args{@required_args};

   my $dsn_defaults = $dp->parse_options($o);
   my $prev_dsn     = $args{prev_dsn};
   my $dsn          = $args{dsn};
   if ( !$dsn ) {
      $args{dsn_string} ||= 'h=' . ($dsn_defaults->{h} || 'localhost');

      $dsn = $dp->parse(
         $args{dsn_string}, $prev_dsn, $dsn_defaults);
   }
   elsif ( $prev_dsn ) {
      $dsn = $dp->copy($prev_dsn, $dsn);
   }

   my $dsn_name = $dp->as_string($dsn, [qw(h P S)])
               || $dp->as_string($dsn, [qw(F)])
               || '';

   my $self = {
      dsn             => $dsn,
      dbh             => $args{dbh},
      dsn_name        => $dsn_name,
      hostname        => '',
      set             => $args{set},
      NAME_lc         => defined($args{NAME_lc}) ? $args{NAME_lc} : 1,
      dbh_set         => 0,
      ask_pass        => $o->get('ask-pass'),
      DSNParser       => $dp,
      is_cluster_node => undef,
      parent          => $args{parent},
   };

   return bless $self, $class;
}

sub connect {
   my ( $self, %opts ) = @_;
   my $dsn = $opts{dsn} || $self->{dsn};
   my $dp  = $self->{DSNParser};

   my $dbh = $self->{dbh};
   if ( !$dbh || !$dbh->ping() ) {
      if ( $self->{ask_pass} && !$self->{asked_for_pass} && !defined $dsn->{p} ) {
         $dsn->{p} = OptionParser::prompt_noecho("Enter MySQL password: ");
         $self->{asked_for_pass} = 1;
      }
      $dbh = $dp->get_dbh(
         $dp->get_cxn_params($dsn),
         {
            AutoCommit => 1,
            %opts,
         },
      );
   }

   $dbh = $self->set_dbh($dbh);
   if ( $opts{dsn} ) {
      $self->{dsn}      = $dsn;
      $self->{dsn_name} = $dp->as_string($dsn, [qw(h P S)])
                       || $dp->as_string($dsn, [qw(F)])
                       || '';

   }
   PTDEBUG && _d($dbh, 'Connected dbh to', $self->{hostname},$self->{dsn_name});
   return $dbh;
}

sub set_dbh {
   my ($self, $dbh) = @_;

   if ( $self->{dbh} && $self->{dbh} == $dbh && $self->{dbh_set} ) {
      PTDEBUG && _d($dbh, 'Already set dbh');
      return $dbh;
   }

   PTDEBUG && _d($dbh, 'Setting dbh');

   $dbh->{FetchHashKeyName} = 'NAME_lc' if $self->{NAME_lc};

   my $sql = 'SELECT @@server_id /*!50038 , @@hostname*/';
   PTDEBUG && _d($dbh, $sql);
   my ($server_id, $hostname) = $dbh->selectrow_array($sql);
   PTDEBUG && _d($dbh, 'hostname:', $hostname, $server_id);
   if ( $hostname ) {
      $self->{hostname} = $hostname;
   }

   if ( $self->{parent} ) {
      PTDEBUG && _d($dbh, 'Setting InactiveDestroy=1 in parent');
      $dbh->{InactiveDestroy} = 1;
   }

   if ( my $set = $self->{set}) {
      $set->($dbh);
   }

   $self->{dbh}     = $dbh;
   $self->{dbh_set} = 1;
   return $dbh;
}

sub lost_connection {
   my ($self, $e) = @_;
   return 0 unless $e;
   return $e =~ m/MySQL server has gone away/
       || $e =~ m/Lost connection to MySQL server/
       || $e =~ m/Server shutdown in progress/;
}

sub dbh {
   my ($self) = @_;
   return $self->{dbh};
}

sub dsn {
   my ($self) = @_;
   return $self->{dsn};
}

sub name {
   my ($self) = @_;
   return $self->{dsn_name} if PERCONA_TOOLKIT_TEST_USE_DSN_NAMES;
   return $self->{hostname} || $self->{dsn_name} || 'unknown host';
}

sub description {
   my ($self) = @_;
   return sprintf("%s -> %s:%s", $self->name(), $self->{dsn}->{h} || 'localhost' , $self->{dsn}->{P} || 'socket');
}

sub get_id {
   my ($self, $cxn) = @_;

   $cxn ||= $self;

   my $unique_id;
   if ($cxn->is_cluster_node()) {  # for cluster we concatenate various variables to maximize id 'uniqueness' across versions
      my $sql  = q{SHOW STATUS LIKE 'wsrep\_local\_index'};
      my (undef, $wsrep_local_index) = $cxn->dbh->selectrow_array($sql);
      PTDEBUG && _d("Got cluster wsrep_local_index: ",$wsrep_local_index);
      $unique_id = $wsrep_local_index."|";
      foreach my $val ('server\_id', 'wsrep\_sst\_receive\_address', 'wsrep\_node\_name', 'wsrep\_node\_address') {
         my $sql = "SHOW VARIABLES LIKE '$val'";
         PTDEBUG && _d($cxn->name, $sql);
         my (undef, $val) = $cxn->dbh->selectrow_array($sql);
         $unique_id .= "|$val";
      }
   } else {
      my $sql  = 'SELECT @@SERVER_ID';
      PTDEBUG && _d($sql);
      $unique_id = $cxn->dbh->selectrow_array($sql);
   }
   PTDEBUG && _d("Generated unique id for cluster:", $unique_id);
   return $unique_id;
}


sub is_cluster_node {
   my ($self, $cxn) = @_;

   $cxn ||= $self;

   my $sql = "SHOW VARIABLES LIKE 'wsrep\_on'";

   my $dbh;
   if ($cxn->isa('DBI::db')) {
      $dbh = $cxn;
      PTDEBUG && _d($sql); #don't invoke name() if it's not a Cxn!
   }
   else {
      $dbh = $cxn->dbh();
      PTDEBUG && _d($cxn->name, $sql);
   }

   my $row = $dbh->selectrow_arrayref($sql);
   return $row && $row->[1] && ($row->[1] eq 'ON' || $row->[1] eq '1') ? 1 : 0;

}

sub remove_duplicate_cxns {
   my ($self, %args) = @_;
   my @cxns     = @{$args{cxns}};
   my $seen_ids = $args{seen_ids} || {};
   PTDEBUG && _d("Removing duplicates from ", join(" ", map { $_->name } @cxns));
   my @trimmed_cxns;

   for my $cxn ( @cxns ) {

      my $id = $cxn->get_id();
      PTDEBUG && _d('Server ID for ', $cxn->name, ': ', $id);

      if ( ! $seen_ids->{$id}++ ) {
         push @trimmed_cxns, $cxn
      }
      else {
         PTDEBUG && _d("Removing ", $cxn->name,
                       ", ID ", $id, ", because we've already seen it");
      }
   }

   return \@trimmed_cxns;
}

sub DESTROY {
   my ($self) = @_;

   PTDEBUG && _d('Destroying cxn');

   if ( $self->{parent} ) {
      PTDEBUG && _d($self->{dbh}, 'Not disconnecting dbh in parent');
   }
   elsif ( $self->{dbh}
           && blessed($self->{dbh})
           && $self->{dbh}->can("disconnect") )
   {
      PTDEBUG && _d($self->{dbh}, 'Disconnecting dbh on', $self->{hostname},
         $self->{dsn_name});
      $self->{dbh}->disconnect();
   }

   return;
}

sub _d {
   my ($package, undef, $line) = caller 0;
   @_ = map { (my $temp = $_) =~ s/\n/\n# /g; $temp; }
        map { defined $_ ? $_ : 'undef' }
        @_;
   print STDERR "# $package:$line $PID ", join(' ', @_), "\n";
}

1;
}
# ###########################################################################
# End Cxn package
# ###########################################################################

# ###########################################################################
# MasterSlave package
# This package is a copy without comments from the original.  The original
# with comments and its test file can be found in the Bazaar repository at,
#   lib/MasterSlave.pm
#   t/lib/MasterSlave.t
# See https://launchpad.net/percona-toolkit for more information.
# ###########################################################################
{
package MasterSlave;

use strict;
use warnings FATAL => 'all';
use English qw(-no_match_vars);
use constant PTDEBUG => $ENV{PTDEBUG} || 0;

sub check_recursion_method {
   my ($methods) = @_;
   if ( @$methods != 1 ) {
      if ( grep({ !m/processlist|hosts/i } @$methods)
            && $methods->[0] !~ /^dsn=/i )
      {
         die  "Invalid combination of recursion methods: "
            . join(", ", map { defined($_) ? $_ : 'undef' } @$methods) . ". "
            . "Only hosts and processlist may be combined.\n"
      }
   }
   else {
      my ($method) = @$methods;
      die "Invalid recursion method: " . ( $method || 'undef' )
         unless $method && $method =~ m/^(?:processlist$|hosts$|none$|cluster$|dsn=)/i;
   }
}

sub new {
   my ( $class, %args ) = @_;
   my @required_args = qw(OptionParser DSNParser Quoter);
   foreach my $arg ( @required_args ) {
      die "I need a $arg argument" unless $args{$arg};
   }
   my $self = {
      %args,
      replication_thread => {},
   };
   return bless $self, $class;
}

sub get_slaves {
   my ($self, %args) = @_;
   my @required_args = qw(make_cxn);
   foreach my $arg ( @required_args ) {
      die "I need a $arg argument" unless $args{$arg};
   }
   my ($make_cxn) = @args{@required_args};

   my $slaves  = [];
   my $dp      = $self->{DSNParser};
   my $methods = $self->_resolve_recursion_methods($args{dsn});

   return $slaves unless @$methods;

   if ( grep { m/processlist|hosts/i } @$methods ) {
      my @required_args = qw(dbh dsn);
      foreach my $arg ( @required_args ) {
         die "I need a $arg argument" unless $args{$arg};
      }
      my ($dbh, $dsn) = @args{@required_args};
      my $o = $self->{OptionParser};

      $self->recurse_to_slaves(
         {  dbh            => $dbh,
            dsn            => $dsn,
            slave_user     => $o->got('slave-user') ? $o->get('slave-user') : '',
            slave_password => $o->got('slave-password') ? $o->get('slave-password') : '',
            callback  => sub {
               my ( $dsn, $dbh, $level, $parent ) = @_;
               return unless $level;
               PTDEBUG && _d('Found slave:', $dp->as_string($dsn));
               my $slave_dsn = $dsn;
               if ($o->got('slave-user')) {
                  $slave_dsn->{u} = $o->get('slave-user');
                  PTDEBUG && _d("Using slave user ".$o->get('slave-user')." on ".$slave_dsn->{h}.":".$slave_dsn->{P});
               }
               if ($o->got('slave-password')) {
                  $slave_dsn->{p} = $o->get('slave-password');
                  PTDEBUG && _d("Slave password set");
               }
               push @$slaves, $make_cxn->(dsn => $slave_dsn, dbh => $dbh);
               return;
            },
         }
      );
   } elsif ( $methods->[0] =~ m/^dsn=/i ) {
      (my $dsn_table_dsn = join ",", @$methods) =~ s/^dsn=//i;
      $slaves = $self->get_cxn_from_dsn_table(
         %args,
         dsn_table_dsn => $dsn_table_dsn,
      );
   }
   elsif ( $methods->[0] =~ m/none/i ) {
      PTDEBUG && _d('Not getting to slaves');
   }
   else {
      die "Unexpected recursion methods: @$methods";
   }

   return $slaves;
}

sub _resolve_recursion_methods {
   my ($self, $dsn) = @_;
   my $o = $self->{OptionParser};
   if ( $o->got('recursion-method') ) {
      return $o->get('recursion-method');
   }
   elsif ( $dsn && ($dsn->{P} || 3306) != 3306 ) {
      PTDEBUG && _d('Port number is non-standard; using only hosts method');
      return [qw(hosts)];
   }
   else {
      return $o->get('recursion-method');
   }
}

sub recurse_to_slaves {
   my ( $self, $args, $level ) = @_;
   $level ||= 0;
   my $dp = $self->{DSNParser};
   my $recurse = $args->{recurse} || $self->{OptionParser}->get('recurse');
   my $dsn = $args->{dsn};
   my $slave_user = $args->{slave_user} || '';
   my $slave_password = $args->{slave_password} || '';

   my $methods = $self->_resolve_recursion_methods($dsn);
   PTDEBUG && _d('Recursion methods:', @$methods);
   if ( lc($methods->[0]) eq 'none' ) {
      PTDEBUG && _d('Not recursing to slaves');
      return;
   }

   my $slave_dsn = $dsn;
   if ($slave_user) {
      $slave_dsn->{u} = $slave_user;
      PTDEBUG && _d("Using slave user $slave_user on ".$slave_dsn->{h}.":".($slave_dsn->{P}?$slave_dsn->{P}:""));
   }
   if ($slave_password) {
      $slave_dsn->{p} = $slave_password;
      PTDEBUG && _d("Slave password set");
   }

   my $dbh;
   eval {
      $dbh = $args->{dbh} || $dp->get_dbh(
         $dp->get_cxn_params($slave_dsn), { AutoCommit => 1 });
      PTDEBUG && _d('Connected to', $dp->as_string($slave_dsn));
   };
   if ( $EVAL_ERROR ) {
      print STDERR "Cannot connect to ", $dp->as_string($slave_dsn), "\n"
         or die "Cannot print: $OS_ERROR";
      return;
   }

   my $sql  = 'SELECT @@SERVER_ID';
   PTDEBUG && _d($sql);
   my ($id) = $dbh->selectrow_array($sql);
   PTDEBUG && _d('Working on server ID', $id);
   my $master_thinks_i_am = $dsn->{server_id};
   if ( !defined $id
       || ( defined $master_thinks_i_am && $master_thinks_i_am != $id )
       || $args->{server_ids_seen}->{$id}++
   ) {
      PTDEBUG && _d('Server ID seen, or not what master said');
      if ( $args->{skip_callback} ) {
         $args->{skip_callback}->($dsn, $dbh, $level, $args->{parent});
      }
      return;
   }

   $args->{callback}->($dsn, $dbh, $level, $args->{parent});

   if ( !defined $recurse || $level < $recurse ) {

      my @slaves =
         grep { !$_->{master_id} || $_->{master_id} == $id } # Only my slaves.
         $self->find_slave_hosts($dp, $dbh, $dsn, $methods);

      foreach my $slave ( @slaves ) {
         PTDEBUG && _d('Recursing from',
            $dp->as_string($dsn), 'to', $dp->as_string($slave));
         $self->recurse_to_slaves(
            { %$args, dsn => $slave, dbh => undef, parent => $dsn, slave_user => $slave_user, $slave_password => $slave_password }, $level + 1 );
      }
   }
}

sub find_slave_hosts {
   my ( $self, $dsn_parser, $dbh, $dsn, $methods ) = @_;

   PTDEBUG && _d('Looking for slaves on', $dsn_parser->as_string($dsn),
      'using methods', @$methods);

   my @slaves;
   METHOD:
   foreach my $method ( @$methods ) {
      my $find_slaves = "_find_slaves_by_$method";
      PTDEBUG && _d('Finding slaves with', $find_slaves);
      @slaves = $self->$find_slaves($dsn_parser, $dbh, $dsn);
      last METHOD if @slaves;
   }

   PTDEBUG && _d('Found', scalar(@slaves), 'slaves');
   return @slaves;
}

sub _find_slaves_by_processlist {
   my ( $self, $dsn_parser, $dbh, $dsn ) = @_;
   my @connected_slaves = $self->get_connected_slaves($dbh);
   my @slaves = $self->_process_slaves_list($dsn_parser, $dsn, \@connected_slaves);
   return @slaves;
}

sub _process_slaves_list {
   my ($self, $dsn_parser, $dsn, $connected_slaves) = @_;
   my @slaves = map  {
      my $slave        = $dsn_parser->parse("h=$_", $dsn);
      $slave->{source} = 'processlist';
      $slave;
   }
   grep { $_ }
   map  {
      my ( $host ) = $_->{host} =~ m/^(.*):\d+$/;
      if ( $host eq 'localhost' ) {
         $host = '127.0.0.1'; # Replication never uses sockets.
      }
      if ($host =~ m/::/) {
          $host = '['.$host.']';
      }
      $host;
   } @$connected_slaves;

   return @slaves;
}

sub _find_slaves_by_hosts {
   my ( $self, $dsn_parser, $dbh, $dsn ) = @_;

   my @slaves;
   my $sql = 'SHOW SLAVE HOSTS';
   PTDEBUG && _d($dbh, $sql);
   @slaves = @{$dbh->selectall_arrayref($sql, { Slice => {} })};

   if ( @slaves ) {
      PTDEBUG && _d('Found some SHOW SLAVE HOSTS info');
      @slaves = map {
         my %hash;
         @hash{ map { lc $_ } keys %$_ } = values %$_;
         my $spec = "h=$hash{host},P=$hash{port}"
            . ( $hash{user} ? ",u=$hash{user}" : '')
            . ( $hash{password} ? ",p=$hash{password}" : '');
         my $dsn           = $dsn_parser->parse($spec, $dsn);
         $dsn->{server_id} = $hash{server_id};
         $dsn->{master_id} = $hash{master_id};
         $dsn->{source}    = 'hosts';
         $dsn;
      } @slaves;
   }

   return @slaves;
}

sub get_connected_slaves {
   my ( $self, $dbh ) = @_;

   my $show = "SHOW GRANTS FOR ";
   my $user = 'CURRENT_USER()';
   my $sql = $show . $user;
   PTDEBUG && _d($dbh, $sql);

   my $proc;
   eval {
      $proc = grep {
         m/ALL PRIVILEGES.*?\*\.\*|PROCESS/
      } @{$dbh->selectcol_arrayref($sql)};
   };
   if ( $EVAL_ERROR ) {

      if ( $EVAL_ERROR =~ m/no such grant defined for user/ ) {
         PTDEBUG && _d('Retrying SHOW GRANTS without host; error:',
            $EVAL_ERROR);
         ($user) = split('@', $user);
         $sql    = $show . $user;
         PTDEBUG && _d($sql);
         eval {
            $proc = grep {
               m/ALL PRIVILEGES.*?\*\.\*|PROCESS/
            } @{$dbh->selectcol_arrayref($sql)};
         };
      }

      die "Failed to $sql: $EVAL_ERROR" if $EVAL_ERROR;
   }
   if ( !$proc ) {
      die "You do not have the PROCESS privilege";
   }

   $sql = 'SHOW FULL PROCESSLIST';
   PTDEBUG && _d($dbh, $sql);
   grep { $_->{command} =~ m/Binlog Dump/i }
   map  { # Lowercase the column names
      my %hash;
      @hash{ map { lc $_ } keys %$_ } = values %$_;
      \%hash;
   }
   @{$dbh->selectall_arrayref($sql, { Slice => {} })};
}

sub is_master_of {
   my ( $self, $master, $slave ) = @_;
   my $master_status = $self->get_master_status($master)
      or die "The server specified as a master is not a master";
   my $slave_status  = $self->get_slave_status($slave)
      or die "The server specified as a slave is not a slave";
   my @connected     = $self->get_connected_slaves($master)
      or die "The server specified as a master has no connected slaves";
   my (undef, $port) = $master->selectrow_array("SHOW VARIABLES LIKE 'port'");

   if ( $port != $slave_status->{master_port} ) {
      die "The slave is connected to $slave_status->{master_port} "
         . "but the master's port is $port";
   }

   if ( !grep { $slave_status->{master_user} eq $_->{user} } @connected ) {
      die "I don't see any slave I/O thread connected with user "
         . $slave_status->{master_user};
   }

   if ( ($slave_status->{slave_io_state} || '')
      eq 'Waiting for master to send event' )
   {
      my ( $master_log_name, $master_log_num )
         = $master_status->{file} =~ m/^(.*?)\.0*([1-9][0-9]*)$/;
      my ( $slave_log_name, $slave_log_num )
         = $slave_status->{master_log_file} =~ m/^(.*?)\.0*([1-9][0-9]*)$/;
      if ( $master_log_name ne $slave_log_name
         || abs($master_log_num - $slave_log_num) > 1 )
      {
         die "The slave thinks it is reading from "
            . "$slave_status->{master_log_file},  but the "
            . "master is writing to $master_status->{file}";
      }
   }
   return 1;
}

sub get_master_dsn {
   my ( $self, $dbh, $dsn, $dsn_parser ) = @_;
   my $master = $self->get_slave_status($dbh) or return undef;
   my $spec   = "h=$master->{master_host},P=$master->{master_port}";
   return       $dsn_parser->parse($spec, $dsn);
}

sub get_slave_status {
   my ( $self, $dbh ) = @_;

   if ( !$self->{not_a_slave}->{$dbh} ) {
      my $sth = $self->{sths}->{$dbh}->{SLAVE_STATUS}
            ||= $dbh->prepare('SHOW SLAVE STATUS');
      PTDEBUG && _d($dbh, 'SHOW SLAVE STATUS');
      $sth->execute();
      my ($sss_rows) = $sth->fetchall_arrayref({}); # Show Slave Status rows

      my $ss;
      if ( $sss_rows && @$sss_rows ) {
          if (scalar @$sss_rows > 1) {
              if (!$self->{channel}) {
                  die 'This server returned more than one row for SHOW SLAVE STATUS but "channel" was not specified on the command line';
              }
              my $slave_use_channels;
              for my $row (@$sss_rows) {
                  $row = { map { lc($_) => $row->{$_} } keys %$row }; # lowercase the keys
                  if ($row->{channel_name}) {
                      $slave_use_channels = 1;
                  }
                  if ($row->{channel_name} eq $self->{channel}) {
                      $ss = $row;
                      last;
                  }
              }
              if (!$ss && $slave_use_channels) {
                 die 'This server is using replication channels but "channel" was not specified on the command line';
              }
          } else {
              if ($sss_rows->[0]->{channel_name} && $sss_rows->[0]->{channel_name} ne $self->{channel}) {
                  die 'This server is using replication channels but "channel" was not specified on the command line';
              } else {
                  $ss = $sss_rows->[0];
              }
          }

          if ( $ss && %$ss ) {
             $ss = { map { lc($_) => $ss->{$_} } keys %$ss }; # lowercase the keys
             return $ss;
          }
          if (!$ss && $self->{channel}) {
              die "Specified channel name is invalid";
          }
      }

      PTDEBUG && _d('This server returns nothing for SHOW SLAVE STATUS');
      $self->{not_a_slave}->{$dbh}++;
  }
}

sub get_master_status {
   my ( $self, $dbh ) = @_;

   if ( $self->{not_a_master}->{$dbh} ) {
      PTDEBUG && _d('Server on dbh', $dbh, 'is not a master');
      return;
   }

   my $sth = $self->{sths}->{$dbh}->{MASTER_STATUS}
         ||= $dbh->prepare('SHOW MASTER STATUS');
   PTDEBUG && _d($dbh, 'SHOW MASTER STATUS');
   $sth->execute();
   my ($ms) = @{$sth->fetchall_arrayref({})};
   PTDEBUG && _d(
      $ms ? map { "$_=" . (defined $ms->{$_} ? $ms->{$_} : '') } keys %$ms
          : '');

   if ( !$ms || scalar keys %$ms < 2 ) {
      PTDEBUG && _d('Server on dbh', $dbh, 'does not seem to be a master');
      $self->{not_a_master}->{$dbh}++;
   }

  return { map { lc($_) => $ms->{$_} } keys %$ms }; # lowercase the keys
}

sub wait_for_master {
   my ( $self, %args ) = @_;
   my @required_args = qw(master_status slave_dbh);
   foreach my $arg ( @required_args ) {
      die "I need a $arg argument" unless $args{$arg};
   }
   my ($master_status, $slave_dbh) = @args{@required_args};
   my $timeout       = $args{timeout} || 60;

   my $result;
   my $waited;
   if ( $master_status ) {
      my $slave_status;
      eval {
          $slave_status = $self->get_slave_status($slave_dbh);
      };
      if ($EVAL_ERROR) {
          return {
              result => undef,
              waited => 0,
              error  =>'Wait for master: this is a multi-master slave but "channel" was not specified on the command line',
          };
      }
      my $server_version = VersionParser->new($slave_dbh);
      my $channel_sql = $server_version > '5.6' && $self->{channel} ? ", '$self->{channel}'" : '';
      my $sql = "SELECT MASTER_POS_WAIT('$master_status->{file}', $master_status->{position}, $timeout $channel_sql)";
      PTDEBUG && _d($slave_dbh, $sql);
      my $start = time;
      ($result) = $slave_dbh->selectrow_array($sql);

      $waited = time - $start;

      PTDEBUG && _d('Result of waiting:', $result);
      PTDEBUG && _d("Waited", $waited, "seconds");
   }
   else {
      PTDEBUG && _d('Not waiting: this server is not a master');
   }

   return {
      result => $result,
      waited => $waited,
   };
}

sub stop_slave {
   my ( $self, $dbh ) = @_;
   my $sth = $self->{sths}->{$dbh}->{STOP_SLAVE}
         ||= $dbh->prepare('STOP SLAVE');
   PTDEBUG && _d($dbh, $sth->{Statement});
   $sth->execute();
}

sub start_slave {
   my ( $self, $dbh, $pos ) = @_;
   if ( $pos ) {
      my $sql = "START SLAVE UNTIL MASTER_LOG_FILE='$pos->{file}', "
              . "MASTER_LOG_POS=$pos->{position}";
      PTDEBUG && _d($dbh, $sql);
      $dbh->do($sql);
   }
   else {
      my $sth = $self->{sths}->{$dbh}->{START_SLAVE}
            ||= $dbh->prepare('START SLAVE');
      PTDEBUG && _d($dbh, $sth->{Statement});
      $sth->execute();
   }
}

sub catchup_to_master {
   my ( $self, $slave, $master, $timeout ) = @_;
   $self->stop_slave($master);
   $self->stop_slave($slave);
   my $slave_status  = $self->get_slave_status($slave);
   my $slave_pos     = $self->repl_posn($slave_status);
   my $master_status = $self->get_master_status($master);
   my $master_pos    = $self->repl_posn($master_status);
   PTDEBUG && _d('Master position:', $self->pos_to_string($master_pos),
      'Slave position:', $self->pos_to_string($slave_pos));

   my $result;
   if ( $self->pos_cmp($slave_pos, $master_pos) < 0 ) {
      PTDEBUG && _d('Waiting for slave to catch up to master');
      $self->start_slave($slave, $master_pos);

      $result = $self->wait_for_master(
            master_status => $master_status,
            slave_dbh     => $slave,
            timeout       => $timeout,
            master_status => $master_status
      );
      if ($result->{error}) {
          die $result->{error};
      }
      if ( !defined $result->{result} ) {
         $slave_status = $self->get_slave_status($slave);
         if ( !$self->slave_is_running($slave_status) ) {
            PTDEBUG && _d('Master position:',
               $self->pos_to_string($master_pos),
               'Slave position:', $self->pos_to_string($slave_pos));
            $slave_pos = $self->repl_posn($slave_status);
            if ( $self->pos_cmp($slave_pos, $master_pos) != 0 ) {
               die "MASTER_POS_WAIT() returned NULL but slave has not "
                  . "caught up to master";
            }
            PTDEBUG && _d('Slave is caught up to master and stopped');
         }
         else {
            die "Slave has not caught up to master and it is still running";
         }
      }
   }
   else {
      PTDEBUG && _d("Slave is already caught up to master");
   }

   return $result;
}

sub catchup_to_same_pos {
   my ( $self, $s1_dbh, $s2_dbh ) = @_;
   $self->stop_slave($s1_dbh);
   $self->stop_slave($s2_dbh);
   my $s1_status = $self->get_slave_status($s1_dbh);
   my $s2_status = $self->get_slave_status($s2_dbh);
   my $s1_pos    = $self->repl_posn($s1_status);
   my $s2_pos    = $self->repl_posn($s2_status);
   if ( $self->pos_cmp($s1_pos, $s2_pos) < 0 ) {
      $self->start_slave($s1_dbh, $s2_pos);
   }
   elsif ( $self->pos_cmp($s2_pos, $s1_pos) < 0 ) {
      $self->start_slave($s2_dbh, $s1_pos);
   }

   $s1_status = $self->get_slave_status($s1_dbh);
   $s2_status = $self->get_slave_status($s2_dbh);
   $s1_pos    = $self->repl_posn($s1_status);
   $s2_pos    = $self->repl_posn($s2_status);

   if ( $self->slave_is_running($s1_status)
     || $self->slave_is_running($s2_status)
     || $self->pos_cmp($s1_pos, $s2_pos) != 0)
   {
      die "The servers aren't both stopped at the same position";
   }

}

sub slave_is_running {
   my ( $self, $slave_status ) = @_;
   return ($slave_status->{slave_sql_running} || 'No') eq 'Yes';
}

sub has_slave_updates {
   my ( $self, $dbh ) = @_;
   my $sql = q{SHOW VARIABLES LIKE 'log_slave_updates'};
   PTDEBUG && _d($dbh, $sql);
   my ($name, $value) = $dbh->selectrow_array($sql);
   return $value && $value =~ m/^(1|ON)$/;
}

sub repl_posn {
   my ( $self, $status ) = @_;
   if ( exists $status->{file} && exists $status->{position} ) {
      return {
         file     => $status->{file},
         position => $status->{position},
      };
   }
   else {
      return {
         file     => $status->{relay_master_log_file},
         position => $status->{exec_master_log_pos},
      };
   }
}

sub get_slave_lag {
   my ( $self, $dbh ) = @_;
   my $stat = $self->get_slave_status($dbh);
   return unless $stat;  # server is not a slave
   return $stat->{seconds_behind_master};
}

sub pos_cmp {
   my ( $self, $a, $b ) = @_;
   return $self->pos_to_string($a) cmp $self->pos_to_string($b);
}

sub short_host {
   my ( $self, $dsn ) = @_;
   my ($host, $port);
   if ( $dsn->{master_host} ) {
      $host = $dsn->{master_host};
      $port = $dsn->{master_port};
   }
   else {
      $host = $dsn->{h};
      $port = $dsn->{P};
   }
   return ($host || '[default]') . ( ($port || 3306) == 3306 ? '' : ":$port" );
}

sub is_replication_thread {
   my ( $self, $query, %args ) = @_;
   return unless $query;

   my $type = lc($args{type} || 'all');
   die "Invalid type: $type"
      unless $type =~ m/^binlog_dump|slave_io|slave_sql|all$/i;

   my $match = 0;
   if ( $type =~ m/binlog_dump|all/i ) {
      $match = 1
         if ($query->{Command} || $query->{command} || '') eq "Binlog Dump";
   }
   if ( !$match ) {
      if ( ($query->{User} || $query->{user} || '') eq "system user" ) {
         PTDEBUG && _d("Slave replication thread");
         if ( $type ne 'all' ) {
            my $state = $query->{State} || $query->{state} || '';

            if ( $state =~ m/^init|end$/ ) {
               PTDEBUG && _d("Special state:", $state);
               $match = 1;
            }
            else {
               my ($slave_sql) = $state =~ m/
                  ^(Waiting\sfor\sthe\snext\sevent
                   |Reading\sevent\sfrom\sthe\srelay\slog
                   |Has\sread\sall\srelay\slog;\swaiting
                   |Making\stemp\sfile
                   |Waiting\sfor\sslave\smutex\son\sexit)/xi;

               $match = $type eq 'slave_sql' &&  $slave_sql ? 1
                      : $type eq 'slave_io'  && !$slave_sql ? 1
                      :                                       0;
            }
         }
         else {
            $match = 1;
         }
      }
      else {
         PTDEBUG && _d('Not system user');
      }

      if ( !defined $args{check_known_ids} || $args{check_known_ids} ) {
         my $id = $query->{Id} || $query->{id};
         if ( $match ) {
            $self->{replication_thread}->{$id} = 1;
         }
         else {
            if ( $self->{replication_thread}->{$id} ) {
               PTDEBUG && _d("Thread ID is a known replication thread ID");
               $match = 1;
            }
         }
      }
   }

   PTDEBUG && _d('Matches', $type, 'replication thread:',
      ($match ? 'yes' : 'no'), '; match:', $match);

   return $match;
}


sub get_replication_filters {
   my ( $self, %args ) = @_;
   my @required_args = qw(dbh);
   foreach my $arg ( @required_args ) {
      die "I need a $arg argument" unless $args{$arg};
   }
   my ($dbh) = @args{@required_args};

   my %filters = ();

   my $status = $self->get_master_status($dbh);
   if ( $status ) {
      map { $filters{$_} = $status->{$_} }
      grep { defined $status->{$_} && $status->{$_} ne '' }
      qw(
         binlog_do_db
         binlog_ignore_db
      );
   }

   $status = $self->get_slave_status($dbh);
   if ( $status ) {
      map { $filters{$_} = $status->{$_} }
      grep { defined $status->{$_} && $status->{$_} ne '' }
      qw(
         replicate_do_db
         replicate_ignore_db
         replicate_do_table
         replicate_ignore_table
         replicate_wild_do_table
         replicate_wild_ignore_table
      );

      my $sql = "SHOW VARIABLES LIKE 'slave_skip_errors'";
      PTDEBUG && _d($dbh, $sql);
      my $row = $dbh->selectrow_arrayref($sql);
      $filters{slave_skip_errors} = $row->[1] if $row->[1] && $row->[1] ne 'OFF';
   }

   return \%filters;
}


sub pos_to_string {
   my ( $self, $pos ) = @_;
   my $fmt  = '%s/%020d';
   return sprintf($fmt, @{$pos}{qw(file position)});
}

sub reset_known_replication_threads {
   my ( $self ) = @_;
   $self->{replication_thread} = {};
   return;
}

sub get_cxn_from_dsn_table {
   my ($self, %args) = @_;
   my @required_args = qw(dsn_table_dsn make_cxn);
   foreach my $arg ( @required_args ) {
      die "I need a $arg argument" unless $args{$arg};
   }
   my ($dsn_table_dsn, $make_cxn) = @args{@required_args};
   PTDEBUG && _d('DSN table DSN:', $dsn_table_dsn);

   my $dp = $self->{DSNParser};
   my $q  = $self->{Quoter};

   my $dsn = $dp->parse($dsn_table_dsn);
   my $dsn_table;
   if ( $dsn->{D} && $dsn->{t} ) {
      $dsn_table = $q->quote($dsn->{D}, $dsn->{t});
   }
   elsif ( $dsn->{t} && $dsn->{t} =~ m/\./ ) {
      $dsn_table = $q->quote($q->split_unquote($dsn->{t}));
   }
   else {
      die "DSN table DSN does not specify a database (D) "
        . "or a database-qualified table (t)";
   }

   my $dsn_tbl_cxn = $make_cxn->(dsn => $dsn);
   my $dbh         = $dsn_tbl_cxn->connect();
   my $sql         = "SELECT dsn FROM $dsn_table ORDER BY id";
   PTDEBUG && _d($sql);
   my $dsn_strings = $dbh->selectcol_arrayref($sql);
   my @cxn;
   if ( $dsn_strings ) {
      foreach my $dsn_string ( @$dsn_strings ) {
         PTDEBUG && _d('DSN from DSN table:', $dsn_string);
         push @cxn, $make_cxn->(dsn_string => $dsn_string);
      }
   }
   return \@cxn;
}

sub _d {
   my ($package, undef, $line) = caller 0;
   @_ = map { (my $temp = $_) =~ s/\n/\n# /g; $temp; }
        map { defined $_ ? $_ : 'undef' }
        @_;
   print STDERR "# $package:$line $PID ", join(' ', @_), "\n";
}

1;
}
# ###########################################################################
# End MasterSlave package
# ###########################################################################

# ###########################################################################
# ReplicaLagWaiter package
# This package is a copy without comments from the original.  The original
# with comments and its test file can be found in the Bazaar repository at,
#   lib/ReplicaLagWaiter.pm
#   t/lib/ReplicaLagWaiter.t
# See https://launchpad.net/percona-toolkit for more information.
# ###########################################################################
{
package ReplicaLagWaiter;

use strict;
use warnings FATAL => 'all';
use English qw(-no_match_vars);
use constant PTDEBUG => $ENV{PTDEBUG} || 0;

use Time::HiRes qw(sleep time);
use Data::Dumper;

sub new {
   my ( $class, %args ) = @_;
   my @required_args = qw(oktorun get_lag sleep max_lag slaves);
   foreach my $arg ( @required_args ) {
      die "I need a $arg argument" unless defined $args{$arg};
   }

   my $self = {
      %args,
   };

   return bless $self, $class;
}

sub wait {
   my ( $self, %args ) = @_;
   my @required_args = qw();
   foreach my $arg ( @required_args ) {
      die "I need a $arg argument" unless $args{$arg};
   }
   my $pr = $args{Progress};

   my $oktorun = $self->{oktorun};
   my $get_lag = $self->{get_lag};
   my $sleep   = $self->{sleep};
   my $slaves  = $self->{slaves};
   my $max_lag = $self->{max_lag};

   my $worst;  # most lagging slave
   my $pr_callback;
   my $pr_first_report;

   ### refresh list of slaves. In: self passed to wait()
   ### Returns: new slave list
   my $pr_refresh_slave_list = sub {
      my ($self) = @_;
      my ($slaves, $refresher) = ($self->{slaves}, $self->{get_slaves_cb});
      return $slaves if ( not defined $refresher );
      my $before = join ' ', sort map {$_->name()} @$slaves;
      $slaves = $refresher->();
      my $after = join ' ', sort map {$_->name()} @$slaves;
      if ($before ne $after) {
         $self->{slaves} = $slaves;
         printf STDERR "Slave set to watch has changed\n  Was: %s\n  Now: %s\n",
            $before, $after;
      }
      return($self->{slaves});
   };

   $slaves = $pr_refresh_slave_list->($self);

   if ( $pr ) {
      # If you use the default Progress report callback, you'll need to
      # to add Transformers.pm to this tool.
      $pr_callback = sub {
         my ($fraction, $elapsed, $remaining, $eta, $completed) = @_;
         my $dsn_name = $worst->{cxn}->name();
         if ( defined $worst->{lag} ) {
            print STDERR "Replica lag is " . ($worst->{lag} || '?')
               . " seconds on $dsn_name.  Waiting.\n";
         }
         else {
            if ($self->{fail_on_stopped_replication}) {
                die 'replication is stopped';
            }
            print STDERR "(1) Replica '$dsn_name' is stopped.  Waiting.\n";
         }
         return;
      };
      $pr->set_callback($pr_callback);

      # If a replic is stopped, don't wait 30s (or whatever interval)
      # to report this.  Instead, report it once, immediately, then
      # keep reporting it every interval.
      $pr_first_report = sub {
         my $dsn_name = $worst->{cxn}->name();
         if ( !defined $worst->{lag} ) {
            if ($self->{fail_on_stopped_replication}) {
                die 'replication is stopped';
            }
            print STDERR "(2) Replica '$dsn_name' is stopped.  Waiting.\n";
         }
         return;
      };
   }

   # First check all slaves.
   my @lagged_slaves = map { {cxn=>$_, lag=>undef} } @$slaves;
   while ( $oktorun->() && @lagged_slaves ) {
      PTDEBUG && _d('Checking slave lag');

      ### while we were waiting our list of slaves may have changed
      $slaves = $pr_refresh_slave_list->($self);
      my $watched = 0;
      @lagged_slaves = grep {
         my $slave_name = $_->{cxn}->name();
         grep {$slave_name eq $_->name()} @{$slaves // []}
                            } @lagged_slaves;

      for my $i ( 0..$#lagged_slaves ) {
         my $lag;
         eval {
             $lag = $get_lag->($lagged_slaves[$i]->{cxn});
         };
         if ($EVAL_ERROR) {
             die $EVAL_ERROR;
         }
         PTDEBUG && _d($lagged_slaves[$i]->{cxn}->name(),
            'slave lag:', $lag);
         if ( !defined $lag || $lag > $max_lag ) {
            $lagged_slaves[$i]->{lag} = $lag;
         }
         else {
            delete $lagged_slaves[$i];
         }
      }

      # Remove slaves that aren't lagging.
      @lagged_slaves = grep { defined $_ } @lagged_slaves;
      if ( @lagged_slaves ) {
         # Sort lag, undef is highest because it means the slave is stopped.
         @lagged_slaves = reverse sort {
              defined $a->{lag} && defined $b->{lag} ? $a->{lag} <=> $b->{lag}
            : defined $a->{lag}                      ? -1
            :                                           1;
         } @lagged_slaves;
         $worst = $lagged_slaves[0];
         PTDEBUG && _d(scalar @lagged_slaves, 'slaves are lagging, worst:',
            $worst->{lag}, 'on', Dumper($worst->{cxn}->dsn()));

         if ( $pr ) {
            # There's no real progress because we can't estimate how long
            # it will take all slaves to catch up.  The progress reports
            # are just to inform the user every 30s which slave is still
            # lagging this most.
            $pr->update(
               sub { return 0; },
               first_report => $pr_first_report,
            );
         }

         PTDEBUG && _d('Calling sleep callback');
         $sleep->($worst->{cxn}, $worst->{lag});
      }
   }

   PTDEBUG && _d('All slaves caught up');
   return;
}

sub _d {
   my ($package, undef, $line) = caller 0;
   @_ = map { (my $temp = $_) =~ s/\n/\n# /g; $temp; }
        map { defined $_ ? $_ : 'undef' }
        @_;
   print STDERR "# $package:$line $PID ", join(' ', @_), "\n";
}

1;
}
# ###########################################################################
# End ReplicaLagWaiter package
# ###########################################################################


# ###########################################################################
# FlowControlWaiter package
# This package is a copy without comments from the original.  The original
# with comments and its test file can be found in the Bazaar repository at,
#   lib/FlowControlWaiter.pm
#   t/lib/FlowControlWaiter.t
# See https://launchpad.net/percona-toolkit for more information.
# ###########################################################################
{
package FlowControlWaiter;

use strict;
use warnings FATAL => 'all';
use English qw(-no_match_vars);
use constant PTDEBUG => $ENV{PTDEBUG} || 0;

use Time::HiRes qw(sleep time);
use Data::Dumper;

sub new {
   my ( $class, %args ) = @_;
   my @required_args = qw(oktorun node sleep max_flow_ctl);
   foreach my $arg ( @required_args ) {
      die "I need a $arg argument" unless defined $args{$arg};
   }

   my $self = {
      %args
   };

   $self->{last_time} = time();

   my (undef, $last_fc_ns) = $self->{node}->selectrow_array('SHOW STATUS LIKE "wsrep_flow_control_paused_ns"');

   $self->{last_fc_secs} = $last_fc_ns/1000_000_000;

   return bless $self, $class;
}

sub wait {
   my ( $self, %args ) = @_;
   my @required_args = qw();
   foreach my $arg ( @required_args ) {
      die "I need a $arg argument" unless $args{$arg};
   }
   my $pr = $args{Progress};

   my $oktorun       = $self->{oktorun};
   my $sleep         = $self->{sleep};
   my $node          = $self->{node};
   my $max_avg       = $self->{max_flow_ctl}/100;

   my $too_much_fc = 1;

   my $pr_callback;
   if ( $pr ) {
      $pr_callback = sub {
         print STDERR "Pausing because PXC Flow Control is active\n";
         return;
      };
      $pr->set_callback($pr_callback);
   }

   while ( $oktorun->() && $too_much_fc ) {
      my $current_time = time();
      my (undef, $current_fc_ns) = $node->selectrow_array('SHOW STATUS LIKE "wsrep_flow_control_paused_ns"');
      my $current_fc_secs = $current_fc_ns/1000_000_000;
      my $current_avg = ($current_fc_secs - $self->{last_fc_secs}) / ($current_time - $self->{last_time});
      if ( $current_avg > $max_avg ) {
         if ( $pr ) {
            $pr->update(sub { return 0; });
         }
         PTDEBUG && _d('Calling sleep callback');
         if ( $self->{simple_progress} ) {
            print STDERR "Waiting for Flow Control to abate\n";
         }
         $sleep->();
      } else {
         $too_much_fc = 0;
      }
      $self->{last_time} = $current_time;
      $self->{last_fc_secs} = $current_fc_secs;


   }

   PTDEBUG && _d('Flow Control is Ok');
   return;
}

sub _d {
   my ($package, undef, $line) = caller 0;
   @_ = map { (my $temp = $_) =~ s/\n/\n# /g; $temp; }
        map { defined $_ ? $_ : 'undef' }
        @_;
   print STDERR "# $package:$line $PID ", join(' ', @_), "\n";
}

1;
}
# ###########################################################################
# End FlowControlWaiter package
# ###########################################################################


# ###########################################################################
# MySQLStatusWaiter package
# This package is a copy without comments from the original.  The original
# with comments and its test file can be found in the Bazaar repository at,
#   lib/MySQLStatusWaiter.pm
#   t/lib/MySQLStatusWaiter.t
# See https://launchpad.net/percona-toolkit for more information.
# ###########################################################################
{
package MySQLStatusWaiter;

use strict;
use warnings FATAL => 'all';
use POSIX qw( ceil );
use English qw(-no_match_vars);
use constant PTDEBUG => $ENV{PTDEBUG} || 0;

sub new {
   my ( $class, %args ) = @_;
   my @required_args = qw(max_spec get_status sleep oktorun);
   foreach my $arg ( @required_args ) {
      die "I need a $arg argument" unless defined $args{$arg};
   }

   PTDEBUG && _d('Parsing spec for max thresholds');
   my $max_val_for = _parse_spec($args{max_spec});
   if ( $max_val_for ) {
      _check_and_set_vals(
         vars             => $max_val_for,
         get_status       => $args{get_status},
         threshold_factor => 0.2, # +20%
      );
   }

   PTDEBUG && _d('Parsing spec for critical thresholds');
   my $critical_val_for = _parse_spec($args{critical_spec} || []);
   if ( $critical_val_for ) {
      _check_and_set_vals(
         vars             => $critical_val_for,
         get_status       => $args{get_status},
         threshold_factor => 1.0, # double (x2; +100%)
      );
   }

   my $self = {
      get_status       => $args{get_status},
      sleep            => $args{sleep},
      oktorun          => $args{oktorun},
      max_val_for      => $max_val_for,
      critical_val_for => $critical_val_for,
   };

   return bless $self, $class;
}

sub _parse_spec {
   my ($spec) = @_;

   return unless $spec && scalar @$spec;

   my %max_val_for;
   foreach my $var_val ( @$spec ) {
      die "Empty or undefined spec\n" unless $var_val;
      $var_val =~ s/^\s+//;
      $var_val =~ s/\s+$//g;

      my ($var, $val) = split /[:=]/, $var_val;
      die "$var_val does not contain a variable\n" unless $var;
      die "$var is not a variable name\n" unless $var =~ m/^[a-zA-Z_]+$/;

      if ( !$val ) {
         PTDEBUG && _d('Will get intial value for', $var, 'later');
         $max_val_for{$var} = undef;
      }
      else {
         die "The value for $var must be a number\n"
            unless $val =~ m/^[\d\.]+$/;
         $max_val_for{$var} = $val;
      }
   }

   return \%max_val_for;
}

sub max_values {
   my ($self) = @_;
   return $self->{max_val_for};
}

sub critical_values {
   my ($self) = @_;
   return $self->{critical_val_for};
}

sub wait {
   my ( $self, %args ) = @_;

   return unless $self->{max_val_for};

   my $pr = $args{Progress}; # optional

   my $oktorun    = $self->{oktorun};
   my $get_status = $self->{get_status};
   my $sleep      = $self->{sleep};

   my %vals_too_high = %{$self->{max_val_for}};
   my $pr_callback;
   if ( $pr ) {
      $pr_callback = sub {
         print STDERR "Pausing because "
            . join(', ',
                 map {
                    "$_="
                    . (defined $vals_too_high{$_} ? $vals_too_high{$_}
                                                  : 'unknown')
                 } sort keys %vals_too_high
              )
            . ".\n";
         return;
      };
      $pr->set_callback($pr_callback);
   }

   while ( $oktorun->() ) {
      PTDEBUG && _d('Checking status variables');
      foreach my $var ( sort keys %vals_too_high ) {
         my $val = $get_status->($var);
         PTDEBUG && _d($var, '=', $val);
         if ( $val
              && exists $self->{critical_val_for}->{$var}
              && $val >= $self->{critical_val_for}->{$var} ) {
            die "$var=$val exceeds its critical threshold "
               . "$self->{critical_val_for}->{$var}\n";
         }
         if ( $val >= $self->{max_val_for}->{$var} ) {
            $vals_too_high{$var} = $val;
         }
         else {
            delete $vals_too_high{$var};
         }
      }

      last unless scalar keys %vals_too_high;

      PTDEBUG && _d(scalar keys %vals_too_high, 'values are too high:',
         %vals_too_high);
      if ( $pr ) {
         $pr->update(sub { return 0; });
      }
      PTDEBUG && _d('Calling sleep callback');
      $sleep->();
      %vals_too_high = %{$self->{max_val_for}}; # recheck all vars
   }

   PTDEBUG && _d('All var vals are low enough');
   return;
}

sub _check_and_set_vals {
   my (%args) = @_;
   my @required_args = qw(vars get_status threshold_factor);
   foreach my $arg ( @required_args ) {
      die "I need a $arg argument" unless defined $args{$arg};
   }
   my ($vars, $get_status, $threshold_factor) = @args{@required_args};

   PTDEBUG && _d('Checking and setting values');
   return unless $vars && scalar %$vars;

   foreach my $var ( keys %$vars ) {
      my $init_val = $get_status->($var);
      die "Variable $var does not exist or its value is undefined\n"
         unless defined $init_val;
      my $val;
      if ( defined $vars->{$var} ) {
         $val = $vars->{$var};
      }
      else {
         PTDEBUG && _d('Initial', $var, 'value:', $init_val);
         $val = ($init_val * $threshold_factor) + $init_val;
         $vars->{$var} = int(ceil($val));
      }
      PTDEBUG && _d('Wait if', $var, '>=', $val);
   }
}

sub _d {
   my ($package, undef, $line) = caller 0;
   @_ = map { (my $temp = $_) =~ s/\n/\n# /g; $temp; }
        map { defined $_ ? $_ : 'undef' }
        @_;
   print STDERR "# $package:$line $PID ", join(' ', @_), "\n";
}

1;
}
# ###########################################################################
# End MySQLStatusWaiter package
# ###########################################################################

# ###########################################################################
# WeightedAvgRate package
# This package is a copy without comments from the original.  The original
# with comments and its test file can be found in the Bazaar repository at,
#   lib/WeightedAvgRate.pm
#   t/lib/WeightedAvgRate.t
# See https://launchpad.net/percona-toolkit for more information.
# ###########################################################################
{
package WeightedAvgRate;

use strict;
use warnings FATAL => 'all';
use English qw(-no_match_vars);
use constant PTDEBUG => $ENV{PTDEBUG} || 0;

sub new {
   my ( $class, %args ) = @_;
   my @required_args = qw(target_t);
   foreach my $arg ( @required_args ) {
      die "I need a $arg argument" unless defined $args{$arg};
   }

   my $self = {
      %args,
      avg_n  => 0,
      avg_t  => 0,
      weight => $args{weight} || 0.75,
   };

   return bless $self, $class;
}

sub update {
   my ($self, $n, $t) = @_;
   PTDEBUG && _d('Master op time:', $n, 'n /', $t, 's');

   if ( $self->{avg_n} && $self->{avg_t} ) {
      $self->{avg_n}    = ($self->{avg_n} * $self->{weight}) + $n;
      $self->{avg_t}    = ($self->{avg_t} * $self->{weight}) + $t;
      $self->{avg_rate} = $self->{avg_n}  / $self->{avg_t};
      PTDEBUG && _d('Weighted avg rate:', $self->{avg_rate}, 'n/s');
   }
   else {
      $self->{avg_n}    = $n;
      $self->{avg_t}    = $t;
      $self->{avg_rate} = $self->{avg_n}  / $self->{avg_t};
      PTDEBUG && _d('Initial avg rate:', $self->{avg_rate}, 'n/s');
   }

   my $new_n = int($self->{avg_rate} * $self->{target_t});
   PTDEBUG && _d('Adjust n to', $new_n);
   return $new_n;
}

sub _d {
   my ($package, undef, $line) = caller 0;
   @_ = map { (my $temp = $_) =~ s/\n/\n# /g; $temp; }
        map { defined $_ ? $_ : 'undef' }
        @_;
   print STDERR "# $package:$line $PID ", join(' ', @_), "\n";
}

1;
}
# ###########################################################################
# End WeightedAvgRate package
# ###########################################################################

# ###########################################################################
# NibbleIterator package
# This package is a copy without comments from the original.  The original
# with comments and its test file can be found in the Bazaar repository at,
#   lib/NibbleIterator.pm
#   t/lib/NibbleIterator.t
# See https://launchpad.net/percona-toolkit for more information.
# ###########################################################################
{
package NibbleIterator;

use strict;
use warnings FATAL => 'all';
use English qw(-no_match_vars);
use constant PTDEBUG => $ENV{PTDEBUG} || 0;

use Data::Dumper;
$Data::Dumper::Indent    = 1;
$Data::Dumper::Sortkeys  = 1;
$Data::Dumper::Quotekeys = 0;

sub new {
   my ( $class, %args ) = @_;
   my @required_args = qw(Cxn tbl chunk_size OptionParser Quoter TableNibbler TableParser);
   foreach my $arg ( @required_args ) {
      die "I need a $arg argument" unless $args{$arg};
   }
   my ($cxn, $tbl, $chunk_size, $o, $q) = @args{@required_args};

   my $nibble_params = can_nibble(%args);

   my %comments = (
      bite   => "bite table",
      nibble => "nibble table",
   );
   if ( $args{comments} ) {
      map  { $comments{$_} = $args{comments}->{$_} }
      grep { defined $args{comments}->{$_}         }
      keys %{$args{comments}};
   }

   my $where      = $o->has('where') ? $o->get('where') : '';
   my $tbl_struct = $tbl->{tbl_struct};
   my $ignore_col = $o->has('ignore-columns')
                  ? ($o->get('ignore-columns') || {})
                  : {};
   my $all_cols   = $o->has('columns')
                  ? ($o->get('columns') || $tbl_struct->{cols})
                  : $tbl_struct->{cols};
   my @cols       = grep { !$ignore_col->{$_} } @$all_cols;
   my $self;
   if ( $nibble_params->{one_nibble} ) {
      my $params = _one_nibble(\%args, \@cols, $where, $tbl, \%comments);
      $self = {
         %args,
         one_nibble         => 1,
         limit              => 0,
         nibble_sql         => $params->{nibble_sql},
         explain_nibble_sql => $params->{explain_nibble_sql},
      };
   } else {
      my $params = _nibble_params($nibble_params, $tbl, \%args, \@cols, $chunk_size, $where, \%comments, $q);
      $self = {
         %args,
         index                => $params->{index},
         limit                => $params->{limit},
         first_lb_sql         => $params->{first_lb_sql},
         last_ub_sql          => $params->{last_ub_sql},
         ub_sql               => $params->{ub_sql},
         nibble_sql           => $params->{nibble_sql},
         explain_first_lb_sql => $params->{explain_first_lb_sql},
         explain_ub_sql       => $params->{explain_ub_sql},
         explain_nibble_sql   => $params->{explain_nibble_sql},
         resume_lb_sql        => $params->{resume_lb_sql},
         sql                  => $params->{sql},
      };
   }

   $self->{row_est}    = $nibble_params->{row_est},
   $self->{nibbleno}   = 0;
   $self->{have_rows}  = 0;
   $self->{rowno}      = 0;
   $self->{oktonibble} = 1;
   $self->{pause_file} = $nibble_params->{pause_file};
   $self->{sleep}      = $args{sleep} || 60;

   $self->{nibble_params} = $nibble_params;
   $self->{tbl}           = $tbl;
   $self->{args}          = \%args;
   $self->{cols}          = \@cols;
   $self->{chunk_size}    = $chunk_size;
   $self->{where}         = $where;
   $self->{comments}      = \%comments;

   return bless $self, $class;
}

sub switch_to_nibble {
    my $self = shift;
    my $params = _nibble_params($self->{nibble_params}, $self->{tbl}, $self->{args}, $self->{cols},
                                $self->{chunk_size}, $self->{where}, $self->{comments}, $self->{Quoter});

    $self->{one_nibble}           = 0;
    $self->{index}                = $params->{index};
    $self->{limit}                = $params->{limit};
    $self->{first_lb_sql}         = $params->{first_lb_sql};
    $self->{last_ub_sql}          = $params->{last_ub_sql};
    $self->{ub_sql}               = $params->{ub_sql};
    $self->{nibble_sql}           = $params->{nibble_sql};
    $self->{explain_first_lb_sql} = $params->{explain_first_lb_sql};
    $self->{explain_ub_sql}       = $params->{explain_ub_sql};
    $self->{explain_nibble_sql}   = $params->{explain_nibble_sql};
    $self->{resume_lb_sql}        = $params->{resume_lb_sql};
    $self->{sql}                  = $params->{sql};
    $self->_get_bounds();
    $self->_prepare_sths();
}

sub _one_nibble {
    my ($args, $cols, $where, $tbl, $comments) = @_;
    my $q        = new Quoter();

      my $nibble_sql
         = ($args->{dml} ? "$args->{dml} " : "SELECT ")
         . ($args->{select} ? $args->{select}
         : join(', ', map{ $tbl->{tbl_struct}->{type_for}->{$_} eq 'enum' ?
                                   "CAST(".$q->quote($_)." AS UNSIGNED)" : $q->quote($_) } @$cols))
         . " FROM $tbl->{name}"
         . ($where ? " WHERE $where" : '')
         . ($args->{lock_in_share_mode} ? " LOCK IN SHARE MODE" : "")
         . " /*$comments->{bite}*/";
      PTDEBUG && _d('One nibble statement:', $nibble_sql);

      my $explain_nibble_sql
         = "EXPLAIN SELECT "
         . ($args->{select} ? $args->{select}
                          : join(', ', map{ $tbl->{tbl_struct}->{type_for}->{$_} eq 'enum'
                          ? "CAST(".$q->quote($_)." AS UNSIGNED)" : $q->quote($_) } @$cols))
         . " FROM $tbl->{name}"
         . ($where ? " WHERE $where" : '')
         . ($args->{lock_in_share_mode} ? " LOCK IN SHARE MODE" : "")
         . " /*explain $comments->{bite}*/";
      PTDEBUG && _d('Explain one nibble statement:', $explain_nibble_sql);

      return {
         one_nibble         => 1,
         limit              => 0,
         nibble_sql         => $nibble_sql,
         explain_nibble_sql => $explain_nibble_sql,
      };
}

sub _nibble_params {
      my ($nibble_params, $tbl, $args, $cols, $chunk_size, $where, $comments, $q) = @_;
      my $index      = $nibble_params->{index}; # brevity
      my $index_cols = $tbl->{tbl_struct}->{keys}->{$index}->{cols};

      my $asc = $args->{TableNibbler}->generate_asc_stmt(
         %$args,
         tbl_struct   => $tbl->{tbl_struct},
         index        => $index,
         n_index_cols => $args->{n_chunk_index_cols},
         cols         => $cols,
         asc_only     => 1,
      );
      PTDEBUG && _d('Ascend params:', Dumper($asc));

      my $force_concat_enums;


      my $from     = "$tbl->{name} FORCE INDEX(`$index`)";
      my $order_by = join(', ', map {$q->quote($_)} @{$index_cols});
      my $order_by_dec = join(' DESC,', map {$q->quote($_)} @{$index_cols});

      my $first_lb_sql
         = "SELECT /*!40001 SQL_NO_CACHE */ "
         . join(', ', map { $tbl->{tbl_struct}->{type_for}->{$_} eq 'enum' ? "CAST(".$q->quote($_)." AS UNSIGNED)" : $q->quote($_)} @{$asc->{scols}})
         . " FROM $from"
         . ($where ? " WHERE $where" : '')
         . " ORDER BY $order_by"
         . " LIMIT 1"
         . " /*first lower boundary*/";
      PTDEBUG && _d('First lower boundary statement:', $first_lb_sql);

      my $resume_lb_sql;
      if ( $args->{resume} ) {
         $resume_lb_sql
            = "SELECT /*!40001 SQL_NO_CACHE */ "
            . join(', ', map { $tbl->{tbl_struct}->{type_for}->{$_} eq 'enum' ? "CAST(".$q->quote($_)." AS UNSIGNED)" : $q->quote($_)} @{$asc->{scols}})
            . " FROM $from"
            . " WHERE " . $asc->{boundaries}->{'>'}
            . ($where ? " AND ($where)" : '')
            . " ORDER BY $order_by"
            . " LIMIT 1"
            . " /*resume lower boundary*/";
         PTDEBUG && _d('Resume lower boundary statement:', $resume_lb_sql);
      }

      my $last_ub_sql
         = "SELECT /*!40001 SQL_NO_CACHE */ "
         . join(', ', map { $tbl->{tbl_struct}->{type_for}->{$_} eq 'enum' ? "CAST(".$q->quote($_)." AS UNSIGNED)" : $q->quote($_)} @{$asc->{scols}})
         . " FROM $from"
         . ($where ? " WHERE $where" : '')
         . " ORDER BY "
         . $order_by_dec . ' DESC'
         . " LIMIT 1"
         . " /*last upper boundary*/";
      PTDEBUG && _d('Last upper boundary statement:', $last_ub_sql);

      my $ub_sql
         = "SELECT /*!40001 SQL_NO_CACHE */ "
         . join(', ', map { $tbl->{tbl_struct}->{type_for}->{$_} eq 'enum' ? "CAST(".$q->quote($_)." AS UNSIGNED)" : $q->quote($_)} @{$asc->{scols}})
         . " FROM $from"
         . " WHERE " . $asc->{boundaries}->{'>='}
                     . ($where ? " AND ($where)" : '')
         . " ORDER BY $order_by"
         . " LIMIT ?, 2"
         . " /*next chunk boundary*/";
      PTDEBUG && _d('Upper boundary statement:', $ub_sql);

      my $nibble_sql
         = ($args->{dml} ? "$args->{dml} " : "SELECT ")
         . ($args->{select} ? $args->{select}
                          : join(', ', map { $tbl->{tbl_struct}->{type_for}->{$_} eq 'enum' ? "CAST(".$q->quote($_)." AS UNSIGNED)" : $q->quote($_)} @{$asc->{cols}}))
         . " FROM $from"
         . " WHERE " . $asc->{boundaries}->{'>='}  # lower boundary
         . " AND "   . $asc->{boundaries}->{'<='}  # upper boundary
         . ($where ? " AND ($where)" : '')
         . ($args->{order_by} ? " ORDER BY $order_by" : "")
         . ($args->{lock_in_share_mode} ? " LOCK IN SHARE MODE" : "")
         . " /*$comments->{nibble}*/";
      PTDEBUG && _d('Nibble statement:', $nibble_sql);

      my $explain_nibble_sql
         = "EXPLAIN SELECT "
         . ($args->{select} ? $args->{select}
                          : join(', ', map { $q->quote($_) } @{$asc->{cols}}))
         . " FROM $from"
         . " WHERE " . $asc->{boundaries}->{'>='}  # lower boundary
         . " AND "   . $asc->{boundaries}->{'<='}  # upper boundary
         . ($where ? " AND ($where)" : '')
         . ($args->{order_by} ? " ORDER BY $order_by" : "")
         . ($args->{lock_in_share_mode} ? " LOCK IN SHARE MODE" : "")
         . " /*explain $comments->{nibble}*/";
      PTDEBUG && _d('Explain nibble statement:', $explain_nibble_sql);

      my $limit = $chunk_size - 1;
      PTDEBUG && _d('Initial chunk size (LIMIT):', $limit);

      my $params = {
         one_nibble           => 0,
         index                => $index,
         limit                => $limit,
         first_lb_sql         => $first_lb_sql,
         last_ub_sql          => $last_ub_sql,
         ub_sql               => $ub_sql,
         nibble_sql           => $nibble_sql,
         explain_first_lb_sql => "EXPLAIN $first_lb_sql",
         explain_ub_sql       => "EXPLAIN $ub_sql",
         explain_nibble_sql   => $explain_nibble_sql,
         resume_lb_sql        => $resume_lb_sql,
         sql                  => {
            columns    => $asc->{scols},
            from       => $from,
            where      => $where,
            boundaries => $asc->{boundaries},
            order_by   => $order_by,
         },
      };
      return $params;
}

sub next {
   my ($self) = @_;

   if ( !$self->{oktonibble} ) {
      PTDEBUG && _d('Not ok to nibble');
      return;
   }

   my %callback_args = (
      Cxn            => $self->{Cxn},
      tbl            => $self->{tbl},
      NibbleIterator => $self,
   );

   if ($self->{nibbleno} == 0) {
      $self->_prepare_sths();
      $self->_get_bounds();
      if ( my $callback = $self->{callbacks}->{init} ) {
         $self->{oktonibble} = $callback->(%callback_args);
         PTDEBUG && _d('init callback returned', $self->{oktonibble});
         if ( !$self->{oktonibble} ) {
            $self->{no_more_boundaries} = 1;
            return;
         }
      }
      if ( !$self->{one_nibble} && !$self->{first_lower} ) {
         PTDEBUG && _d('No first lower boundary, table must be empty');
         $self->{no_more_boundaries} = 1;
         return;
      }
   }

   NIBBLE:
   while ( $self->{have_rows} || $self->_next_boundaries() ) {
      if ($self->{pause_file}) {
         while(-f $self->{pause_file}) {
            print "Sleeping $self->{sleep} seconds because $self->{pause_file} exists\n";
            my $dbh = $self->{Cxn}->dbh();
            if ( !$dbh || !$dbh->ping() ) {
               eval { $dbh = $self->{Cxn}->connect() }; # connect or die trying
               if ( $EVAL_ERROR ) {
                  chomp $EVAL_ERROR;
                  die "Lost connection to " . $self->{Cxn}->name() . " while waiting for "
                  . "replica lag ($EVAL_ERROR)\n";
               }
            }
            $dbh->do("SELECT 'nibble iterator keepalive'");
            sleep($self->{sleep});
         }
      }

      if ( !$self->{have_rows} ) {
         $self->{nibbleno}++;
         PTDEBUG && _d('Nibble:', $self->{nibble_sth}->{Statement}, 'params:',
            join(', ', (@{$self->{lower} || []}, @{$self->{upper} || []})));
         if ( my $callback = $self->{callbacks}->{exec_nibble} ) {
            $self->{have_rows} = $callback->(%callback_args);
         }
         else {
            $self->{nibble_sth}->execute(@{$self->{lower}}, @{$self->{upper}});
            $self->{have_rows} = $self->{nibble_sth}->rows();
         }
         PTDEBUG && _d($self->{have_rows}, 'rows in nibble', $self->{nibbleno});
      }

      if ( $self->{have_rows} ) {
         my $row = $self->{nibble_sth}->fetchrow_arrayref();
         if ( $row ) {
            $self->{rowno}++;
            PTDEBUG && _d('Row', $self->{rowno}, 'in nibble',$self->{nibbleno});
            return [ @$row ];
         }
      }

      PTDEBUG && _d('No rows in nibble or nibble skipped');
      if ( my $callback = $self->{callbacks}->{after_nibble} ) {
         $callback->(%callback_args);
      }
      $self->{rowno}     = 0;
      $self->{have_rows} = 0;

   }

   PTDEBUG && _d('Done nibbling');
   if ( my $callback = $self->{callbacks}->{done} ) {
      $callback->(%callback_args);
   }

   return;
}

sub nibble_number {
   my ($self) = @_;
   return $self->{nibbleno};
}

sub set_nibble_number {
   my ($self, $n) = @_;
   die "I need a number" unless $n;
   $self->{nibbleno} = $n;
   PTDEBUG && _d('Set new nibble number:', $n);
   return;
}

sub nibble_index {
   my ($self) = @_;
   return $self->{index};
}

sub statements {
   my ($self) = @_;
   return {
      explain_first_lower_boundary => $self->{explain_first_lb_sth},
      nibble                       => $self->{nibble_sth},
      explain_nibble               => $self->{explain_nibble_sth},
      upper_boundary               => $self->{ub_sth},
      explain_upper_boundary       => $self->{explain_ub_sth},
   }
}

sub boundaries {
   my ($self) = @_;
   return {
      first_lower => $self->{first_lower},
      lower       => $self->{lower},
      upper       => $self->{upper},
      next_lower  => $self->{next_lower},
      last_upper  => $self->{last_upper},
   };
}

sub set_boundary {
   my ($self, $boundary, $values) = @_;
   die "I need a boundary parameter"
      unless $boundary;
   die "Invalid boundary: $boundary"
      unless $boundary =~ m/^(?:lower|upper|next_lower|last_upper)$/;
   die "I need a values arrayref parameter"
      unless $values && ref $values eq 'ARRAY';
   $self->{$boundary} = $values;
   PTDEBUG && _d('Set new', $boundary, 'boundary:', Dumper($values));
   return;
}

sub one_nibble {
   my ($self) = @_;
   return $self->{one_nibble};
}

sub limit {
   my ($self) = @_;
   return $self->{limit};
}

sub set_chunk_size {
   my ($self, $limit) = @_;
   return if $self->{one_nibble};
   die "Chunk size must be > 0" unless $limit;
   $self->{limit} = $limit - 1;
   PTDEBUG && _d('Set new chunk size (LIMIT):', $limit);
   return;
}

sub sql {
   my ($self) = @_;
   return $self->{sql};
}

sub more_boundaries {
   my ($self) = @_;
   return !$self->{no_more_boundaries};
}

sub row_estimate {
   my ($self) = @_;
   return $self->{row_est};
}

sub can_nibble {
   my (%args) = @_;
   my @required_args = qw(Cxn tbl chunk_size OptionParser TableParser);
   foreach my $arg ( @required_args ) {
      die "I need a $arg argument" unless $args{$arg};
   }
   my ($cxn, $tbl, $chunk_size, $o) = @args{@required_args};

   my $where = $o->has('where') ? $o->get('where') : '';

   my ($row_est, $mysql_index) = get_row_estimate(
      Cxn   => $cxn,
      tbl   => $tbl,
      where => $where,
   );

   if ( !$where ) {
      $mysql_index = undef;
   }

   my $chunk_size_limit = $o->get('chunk-size-limit') || 1;
   my $one_nibble = !defined $args{one_nibble} || $args{one_nibble}
                  ? $row_est <= $chunk_size * $chunk_size_limit
                  : 0;
   PTDEBUG && _d('One nibble:', $one_nibble ? 'yes' : 'no');

   if ( $args{resume}
        && !defined $args{resume}->{lower_boundary}
        && !defined $args{resume}->{upper_boundary} ) {
      PTDEBUG && _d('Resuming from one nibble table');
      $one_nibble = 1;
   }

   my $index = _find_best_index(%args, mysql_index => $mysql_index);
   if ( !$index && !$one_nibble ) {
      die "There is no good index and the table is oversized.";
   }

   my $pause_file = ($o->has('pause-file') && $o->get('pause-file')) || undef;

   return {
      row_est     => $row_est,      # nibble about this many rows
      index       => $index,        # using this index
      one_nibble  => $one_nibble,   # if the table fits in one nibble/chunk
      pause_file  => $pause_file,
   };
}

sub _find_best_index {
   my (%args) = @_;
   my @required_args = qw(Cxn tbl TableParser);
   my ($cxn, $tbl, $tp) = @args{@required_args};
   my $tbl_struct = $tbl->{tbl_struct};
   my $indexes    = $tbl_struct->{keys};

   my $best_index;
   my $want_index = $args{chunk_index};
   if ( $want_index ) {
      PTDEBUG && _d('User wants to use index', $want_index);
      if ( !exists $indexes->{$want_index} ) {
         PTDEBUG && _d('Cannot use user index because it does not exist');
         $want_index = undef;
      } else {
         $best_index = $want_index;
      }
   }

   if ( !$best_index && !$want_index && $args{mysql_index} ) {
      PTDEBUG && _d('MySQL wants to use index', $args{mysql_index});
      $want_index = $args{mysql_index};
   }


   my @possible_indexes;
   if ( !$best_index && $want_index ) {
      if ( $indexes->{$want_index}->{is_unique} ) {
         PTDEBUG && _d('Will use wanted index');
         $best_index = $want_index;
      }
      else {
         PTDEBUG && _d('Wanted index is a possible index');
         push @possible_indexes, $want_index;
      }
   }

   if (!$best_index) {
      PTDEBUG && _d('Auto-selecting best index');
      foreach my $index ( $tp->sort_indexes($tbl_struct) ) {
         if ( $index eq 'PRIMARY' || $indexes->{$index}->{is_unique} ) {
            $best_index = $index;
            last;
         }
         else {
            push @possible_indexes, $index;
         }
      }
   }

   if ( !$best_index && @possible_indexes ) {
      PTDEBUG && _d('No PRIMARY or unique indexes;',
         'will use index with highest cardinality');
      foreach my $index ( @possible_indexes ) {
         $indexes->{$index}->{cardinality} = _get_index_cardinality(
            %args,
            index => $index,
         );
      }
      @possible_indexes = sort {
         my $cmp
            = $indexes->{$b}->{cardinality} <=> $indexes->{$a}->{cardinality};
         if ( $cmp == 0 ) {
            $cmp = scalar @{$indexes->{$b}->{cols}}
               <=> scalar @{$indexes->{$a}->{cols}};
         }
         $cmp;
      } @possible_indexes;
      $best_index = $possible_indexes[0];
   }

   PTDEBUG && _d('Best index:', $best_index);
   return $best_index;
}

sub _get_index_cardinality {
   my (%args) = @_;
   my @required_args = qw(Cxn tbl index);
   my ($cxn, $tbl, $index) = @args{@required_args};

   my $sql = "SHOW INDEXES FROM $tbl->{name} "
           . "WHERE Key_name = '$index'";
   PTDEBUG && _d($sql);
   my $cardinality = 1;
   my $dbh         = $cxn->dbh();
   my $key_name    = $dbh && ($dbh->{FetchHashKeyName} || '') eq 'NAME_lc'
                   ? 'key_name'
                   : 'Key_name';
   my $rows = $dbh->selectall_hashref($sql, $key_name);
   foreach my $row ( values %$rows ) {
      $cardinality *= $row->{cardinality} if $row->{cardinality};
   }
   PTDEBUG && _d('Index', $index, 'cardinality:', $cardinality);
   return $cardinality;
}

sub get_row_estimate {
   my (%args) = @_;
   my @required_args = qw(Cxn tbl);
   foreach my $arg ( @required_args ) {
      die "I need a $arg argument" unless $args{$arg};
   }
   my ($cxn, $tbl) = @args{@required_args};

   my $sql = "EXPLAIN SELECT * FROM $tbl->{name} "
           . "WHERE " . ($args{where} || '1=1');
   PTDEBUG && _d($sql);
   my $expl = $cxn->dbh()->selectrow_hashref($sql);
   PTDEBUG && _d(Dumper($expl));
   my $mysql_index = $expl->{key} || '';
   if ( $mysql_index ne 'PRIMARY' ) {
      $mysql_index = lc($mysql_index);
   }
   return ($expl->{rows} || 0), $mysql_index;
}

sub _prepare_sths {
   my ($self) = @_;
   PTDEBUG && _d('Preparing statement handles');

   my $dbh = $self->{Cxn}->dbh();

   $self->{nibble_sth}         = $dbh->prepare($self->{nibble_sql});
   $self->{explain_nibble_sth} = $dbh->prepare($self->{explain_nibble_sql});

   if ( !$self->{one_nibble} ) {
      $self->{explain_first_lb_sth} = $dbh->prepare($self->{explain_first_lb_sql});
      $self->{ub_sth}               = $dbh->prepare($self->{ub_sql});
      $self->{explain_ub_sth}       = $dbh->prepare($self->{explain_ub_sql});
   }

   return;
}

sub _get_bounds {
   my ($self) = @_;

   if ( $self->{one_nibble} ) {
      if ( $self->{resume} ) {
         $self->{no_more_boundaries} = 1;
      }
      return;
   }

   my $dbh = $self->{Cxn}->dbh();

   $self->{first_lower} = $dbh->selectrow_arrayref($self->{first_lb_sql});
   PTDEBUG && _d('First lower boundary:', Dumper($self->{first_lower}));

   if ( my $nibble = $self->{resume} ) {
      if (    defined $nibble->{lower_boundary}
           && defined $nibble->{upper_boundary} ) {
         my $sth = $dbh->prepare($self->{resume_lb_sql});
         my @ub  = split ',', $nibble->{upper_boundary};
         PTDEBUG && _d($sth->{Statement}, 'params:', @ub);
         $sth->execute(@ub);
         $self->{next_lower} = $sth->fetchrow_arrayref();
         $sth->finish();
      }
   }
   else {
      $self->{next_lower}  = $self->{first_lower};
   }
   PTDEBUG && _d('Next lower boundary:', Dumper($self->{next_lower}));

   if ( !$self->{next_lower} ) {
      PTDEBUG && _d('At end of table, or no more boundaries to resume');
      $self->{no_more_boundaries} = 1;

      $self->{last_upper} = $dbh->selectrow_arrayref($self->{last_ub_sql});
      PTDEBUG && _d('Last upper boundary:', Dumper($self->{last_upper}));
   }

   return;
}

sub _next_boundaries {
   my ($self) = @_;

   if ( $self->{no_more_boundaries} ) {
      PTDEBUG && _d('No more boundaries');
      return; # stop nibbling
   }

   if ( $self->{one_nibble} ) {
      $self->{lower} = $self->{upper} = [];
      $self->{no_more_boundaries} = 1;  # for next call
      return 1; # continue nibbling
   }



   if ( $self->identical_boundaries($self->{lower}, $self->{next_lower}) ) {
      PTDEBUG && _d('Infinite loop detected');
      my $tbl     = $self->{tbl};
      my $index   = $tbl->{tbl_struct}->{keys}->{$self->{index}};
      my $n_cols  = scalar @{$index->{cols}};
      my $chunkno = $self->{nibbleno};

      die "Possible infinite loop detected!  "
         . "The lower boundary for chunk $chunkno is "
         . "<" . join(', ', @{$self->{lower}}) . "> and the lower "
         . "boundary for chunk " . ($chunkno + 1) . " is also "
         . "<" . join(', ', @{$self->{next_lower}}) . ">.  "
         . "This usually happens when using a non-unique single "
         . "column index.  The current chunk index for table "
         . "$tbl->{db}.$tbl->{tbl} is $self->{index} which is"
         . ($index->{is_unique} ? '' : ' not') . " unique and covers "
         . ($n_cols > 1 ? "$n_cols columns" : "1 column") . ".\n";
   }
   $self->{lower} = $self->{next_lower};

   if ( my $callback = $self->{callbacks}->{next_boundaries} ) {
      my $oktonibble = $callback->(
         Cxn            => $self->{Cxn},
         tbl            => $self->{tbl},
         NibbleIterator => $self,
      );
      PTDEBUG && _d('next_boundaries callback returned', $oktonibble);
      if ( !$oktonibble ) {
         $self->{no_more_boundaries} = 1;
         return; # stop nibbling
      }
   }


   PTDEBUG && _d($self->{ub_sth}->{Statement}, 'params:',
      join(', ', @{$self->{lower}}), $self->{limit});
   $self->{ub_sth}->execute(@{$self->{lower}}, $self->{limit});
   my $boundary = $self->{ub_sth}->fetchall_arrayref();
   PTDEBUG && _d('Next boundary:', Dumper($boundary));
   if ( $boundary && @$boundary ) {
      $self->{upper} = $boundary->[0];

      if ( $boundary->[1] ) {
         $self->{next_lower} = $boundary->[1];
      }
      else {
         PTDEBUG && _d('End of table boundary:', Dumper($boundary->[0]));
         $self->{no_more_boundaries} = 1;  # for next call

         $self->{last_upper} = $boundary->[0];
      }
   }
   else {
      my $dbh = $self->{Cxn}->dbh();
      $self->{upper} = $dbh->selectrow_arrayref($self->{last_ub_sql});
      PTDEBUG && _d('Last upper boundary:', Dumper($self->{upper}));
      $self->{no_more_boundaries} = 1;  # for next call

      $self->{last_upper} = $self->{upper};
   }
   $self->{ub_sth}->finish();

   return 1; # continue nibbling
}

sub identical_boundaries {
   my ($self, $b1, $b2) = @_;

   return 0 if ($b1 && !$b2) || (!$b1 && $b2);

   return 1 if !$b1 && !$b2;

   die "Boundaries have different numbers of values"
      if scalar @$b1 != scalar @$b2;  # shouldn't happen
   my $n_vals = scalar @$b1;
   for my $i ( 0..($n_vals-1) ) {
      return 0 if ($b1->[$i] || '') ne ($b2->[$i] || ''); # diff
   }
   return 1;
}

sub DESTROY {
   my ( $self ) = @_;
   foreach my $key ( keys %$self ) {
      if ( $key =~ m/_sth$/ ) {
         PTDEBUG && _d('Finish', $key);
         $self->{$key}->finish();
      }
   }
   return;
}

sub _d {
   my ($package, undef, $line) = caller 0;
   @_ = map { (my $temp = $_) =~ s/\n/\n# /g; $temp; }
        map { defined $_ ? $_ : 'undef' }
        @_;
   print STDERR "# $package:$line $PID ", join(' ', @_), "\n";
}

1;
}
# ###########################################################################
# End NibbleIterator package
# ###########################################################################

# ###########################################################################
# Transformers package
# This package is a copy without comments from the original.  The original
# with comments and its test file can be found in the Bazaar repository at,
#   lib/Transformers.pm
#   t/lib/Transformers.t
# See https://launchpad.net/percona-toolkit for more information.
# ###########################################################################
{
package Transformers;

use strict;
use warnings FATAL => 'all';
use English qw(-no_match_vars);
use constant PTDEBUG => $ENV{PTDEBUG} || 0;

use Time::Local qw(timegm timelocal);
use Digest::MD5 qw(md5_hex);
use B qw();

BEGIN {
   require Exporter;
   our @ISA         = qw(Exporter);
   our %EXPORT_TAGS = ();
   our @EXPORT      = ();
   our @EXPORT_OK   = qw(
      micro_t
      percentage_of
      secs_to_time
      time_to_secs
      shorten
      ts
      parse_timestamp
      unix_timestamp
      any_unix_timestamp
      make_checksum
      crc32
      encode_json
   );
}

our $mysql_ts  = qr/(\d\d)(\d\d)(\d\d) +(\d+):(\d+):(\d+)(\.\d+)?/;
our $proper_ts = qr/(\d\d\d\d)-(\d\d)-(\d\d)[T ](\d\d):(\d\d):(\d\d)(\.\d+)?/;
our $n_ts      = qr/(\d{1,5})([shmd]?)/; # Limit \d{1,5} because \d{6} looks

sub micro_t {
   my ( $t, %args ) = @_;
   my $p_ms = defined $args{p_ms} ? $args{p_ms} : 0;  # precision for ms vals
   my $p_s  = defined $args{p_s}  ? $args{p_s}  : 0;  # precision for s vals
   my $f;

   $t = 0 if $t < 0;

   $t = sprintf('%.17f', $t) if $t =~ /e/;

   $t =~ s/\.(\d{1,6})\d*/\.$1/;

   if ($t > 0 && $t <= 0.000999) {
      $f = ($t * 1000000) . 'us';
   }
   elsif ($t >= 0.001000 && $t <= 0.999999) {
      $f = sprintf("%.${p_ms}f", $t * 1000);
      $f = ($f * 1) . 'ms'; # * 1 to remove insignificant zeros
   }
   elsif ($t >= 1) {
      $f = sprintf("%.${p_s}f", $t);
      $f = ($f * 1) . 's'; # * 1 to remove insignificant zeros
   }
   else {
      $f = 0;  # $t should = 0 at this point
   }

   return $f;
}

sub percentage_of {
   my ( $is, $of, %args ) = @_;
   my $p   = $args{p} || 0; # float precision
   my $fmt = $p ? "%.${p}f" : "%d";
   return sprintf $fmt, ($is * 100) / ($of ||= 1);
}

sub secs_to_time {
   my ( $secs, $fmt ) = @_;
   $secs ||= 0;
   return '00:00' unless $secs;

   $fmt ||= $secs >= 86_400 ? 'd'
          : $secs >= 3_600  ? 'h'
          :                   'm';

   return
      $fmt eq 'd' ? sprintf(
         "%d+%02d:%02d:%02d",
         int($secs / 86_400),
         int(($secs % 86_400) / 3_600),
         int(($secs % 3_600) / 60),
         $secs % 60)
      : $fmt eq 'h' ? sprintf(
         "%02d:%02d:%02d",
         int(($secs % 86_400) / 3_600),
         int(($secs % 3_600) / 60),
         $secs % 60)
      : sprintf(
         "%02d:%02d",
         int(($secs % 3_600) / 60),
         $secs % 60);
}

sub time_to_secs {
   my ( $val, $default_suffix ) = @_;
   die "I need a val argument" unless defined $val;
   my $t = 0;
   my ( $prefix, $num, $suffix ) = $val =~ m/([+-]?)(\d+)([a-z])?$/;
   $suffix = $suffix || $default_suffix || 's';
   if ( $suffix =~ m/[smhd]/ ) {
      $t = $suffix eq 's' ? $num * 1        # Seconds
         : $suffix eq 'm' ? $num * 60       # Minutes
         : $suffix eq 'h' ? $num * 3600     # Hours
         :                  $num * 86400;   # Days

      $t *= -1 if $prefix && $prefix eq '-';
   }
   else {
      die "Invalid suffix for $val: $suffix";
   }
   return $t;
}

sub shorten {
   my ( $num, %args ) = @_;
   my $p = defined $args{p} ? $args{p} : 2;     # float precision
   my $d = defined $args{d} ? $args{d} : 1_024; # divisor
   my $n = 0;
   my @units = ('', qw(k M G T P E Z Y));
   while ( $num >= $d && $n < @units - 1 ) {
      $num /= $d;
      ++$n;
   }
   return sprintf(
      $num =~ m/\./ || $n
         ? '%1$.'.$p.'f%2$s'
         : '%1$d',
      $num, $units[$n]);
}

sub ts {
   my ( $time, $gmt ) = @_;
   my ( $sec, $min, $hour, $mday, $mon, $year )
      = $gmt ? gmtime($time) : localtime($time);
   $mon  += 1;
   $year += 1900;
   my $val = sprintf("%d-%02d-%02dT%02d:%02d:%02d",
      $year, $mon, $mday, $hour, $min, $sec);
   if ( my ($us) = $time =~ m/(\.\d+)$/ ) {
      $us = sprintf("%.6f", $us);
      $us =~ s/^0\././;
      $val .= $us;
   }
   return $val;
}

sub parse_timestamp {
   my ( $val ) = @_;
   if ( my($y, $m, $d, $h, $i, $s, $f)
         = $val =~ m/^$mysql_ts$/ )
   {
      return sprintf "%d-%02d-%02d %02d:%02d:"
                     . (defined $f ? '%09.6f' : '%02d'),
                     $y + 2000, $m, $d, $h, $i, (defined $f ? $s + $f : $s);
   }
   elsif ( $val =~ m/^$proper_ts$/ ) {
      return $val;
   }
   return $val;
}

sub unix_timestamp {
   my ( $val, $gmt ) = @_;
   if ( my($y, $m, $d, $h, $i, $s, $us) = $val =~ m/^$proper_ts$/ ) {
      $val = $gmt
         ? timegm($s, $i, $h, $d, $m - 1, $y)
         : timelocal($s, $i, $h, $d, $m - 1, $y);
      if ( defined $us ) {
         $us = sprintf('%.6f', $us);
         $us =~ s/^0\././;
         $val .= $us;
      }
   }
   return $val;
}

sub any_unix_timestamp {
   my ( $val, $callback ) = @_;

   if ( my ($n, $suffix) = $val =~ m/^$n_ts$/ ) {
      $n = $suffix eq 's' ? $n            # Seconds
         : $suffix eq 'm' ? $n * 60       # Minutes
         : $suffix eq 'h' ? $n * 3600     # Hours
         : $suffix eq 'd' ? $n * 86400    # Days
         :                  $n;           # default: Seconds
      PTDEBUG && _d('ts is now - N[shmd]:', $n);
      return time - $n;
   }
   elsif ( $val =~ m/^\d{9,}/ ) {
      PTDEBUG && _d('ts is already a unix timestamp');
      return $val;
   }
   elsif ( my ($ymd, $hms) = $val =~ m/^(\d{6})(?:\s+(\d+:\d+:\d+))?/ ) {
      PTDEBUG && _d('ts is MySQL slow log timestamp');
      $val .= ' 00:00:00' unless $hms;
      return unix_timestamp(parse_timestamp($val));
   }
   elsif ( ($ymd, $hms) = $val =~ m/^(\d{4}-\d\d-\d\d)(?:[T ](\d+:\d+:\d+))?/) {
      PTDEBUG && _d('ts is properly formatted timestamp');
      $val .= ' 00:00:00' unless $hms;
      return unix_timestamp($val);
   }
   else {
      PTDEBUG && _d('ts is MySQL expression');
      return $callback->($val) if $callback && ref $callback eq 'CODE';
   }

   PTDEBUG && _d('Unknown ts type:', $val);
   return;
}

sub make_checksum {
   my ( $val ) = @_;
   my $checksum = uc substr(md5_hex($val), -16);
   PTDEBUG && _d($checksum, 'checksum for', $val);
   return $checksum;
}

sub crc32 {
   my ( $string ) = @_;
   return unless $string;
   my $poly = 0xEDB88320;
   my $crc  = 0xFFFFFFFF;
   foreach my $char ( split(//, $string) ) {
      my $comp = ($crc ^ ord($char)) & 0xFF;
      for ( 1 .. 8 ) {
         $comp = $comp & 1 ? $poly ^ ($comp >> 1) : $comp >> 1;
      }
      $crc = (($crc >> 8) & 0x00FFFFFF) ^ $comp;
   }
   return $crc ^ 0xFFFFFFFF;
}

my $got_json = eval { require JSON };
sub encode_json {
   return JSON::encode_json(@_) if $got_json;
   my ( $data ) = @_;
   return (object_to_json($data) || '');
}


sub object_to_json {
   my ($obj) = @_;
   my $type  = ref($obj);

   if($type eq 'HASH'){
      return hash_to_json($obj);
   }
   elsif($type eq 'ARRAY'){
      return array_to_json($obj);
   }
   else {
      return value_to_json($obj);
   }
}

sub hash_to_json {
   my ($obj) = @_;
   my @res;
   for my $k ( sort { $a cmp $b } keys %$obj ) {
      push @res, string_to_json( $k )
         .  ":"
         . ( object_to_json( $obj->{$k} ) || value_to_json( $obj->{$k} ) );
   }
   return '{' . ( @res ? join( ",", @res ) : '' )  . '}';
}

sub array_to_json {
   my ($obj) = @_;
   my @res;

   for my $v (@$obj) {
      push @res, object_to_json($v) || value_to_json($v);
   }

   return '[' . ( @res ? join( ",", @res ) : '' ) . ']';
}

sub value_to_json {
   my ($value) = @_;

   return 'null' if(!defined $value);

   my $b_obj = B::svref_2object(\$value);  # for round trip problem
   my $flags = $b_obj->FLAGS;
   return $value # as is
      if $flags & ( B::SVp_IOK | B::SVp_NOK ) and !( $flags & B::SVp_POK ); # SvTYPE is IV or NV?

   my $type = ref($value);

   if( !$type ) {
      return string_to_json($value);
   }
   else {
      return 'null';
   }

}

my %esc = (
   "\n" => '\n',
   "\r" => '\r',
   "\t" => '\t',
   "\f" => '\f',
   "\b" => '\b',
   "\"" => '\"',
   "\\" => '\\\\',
   "\'" => '\\\'',
);

sub string_to_json {
   my ($arg) = @_;

   $arg =~ s/([\x22\x5c\n\r\t\f\b])/$esc{$1}/g;
   $arg =~ s/\//\\\//g;
   $arg =~ s/([\x00-\x08\x0b\x0e-\x1f])/'\\u00' . unpack('H2', $1)/eg;

   utf8::upgrade($arg);
   utf8::encode($arg);

   return '"' . $arg . '"';
}

sub _d {
   my ($package, undef, $line) = caller 0;
   @_ = map { (my $temp = $_) =~ s/\n/\n# /g; $temp; }
        map { defined $_ ? $_ : 'undef' }
        @_;
   print STDERR "# $package:$line $PID ", join(' ', @_), "\n";
}

1;
}
# ###########################################################################
# End Transformers package
# ###########################################################################

# ###########################################################################
# CleanupTask package
# This package is a copy without comments from the original.  The original
# with comments and its test file can be found in the Bazaar repository at,
#   lib/CleanupTask.pm
#   t/lib/CleanupTask.t
# See https://launchpad.net/percona-toolkit for more information.
# ###########################################################################
{
package CleanupTask;

use strict;
use warnings FATAL => 'all';
use English qw(-no_match_vars);
use constant PTDEBUG => $ENV{PTDEBUG} || 0;

sub new {
   my ( $class, $task ) = @_;
   die "I need a task parameter" unless $task;
   die "The task parameter must be a coderef" unless ref $task eq 'CODE';
   my $self = {
      task => $task,
   };
   open $self->{stdout_copy}, ">&=", *STDOUT
      or die "Cannot dup stdout: $OS_ERROR";
   open $self->{stderr_copy}, ">&=", *STDERR
      or die "Cannot dup stderr: $OS_ERROR";
   PTDEBUG && _d('Created cleanup task', $task);
   return bless $self, $class;
}

sub DESTROY {
   my ($self) = @_;
   my $task = $self->{task};
   if ( ref $task ) {
      PTDEBUG && _d('Calling cleanup task', $task);
      open local(*STDOUT), ">&=", $self->{stdout_copy}
         if $self->{stdout_copy};
      open local(*STDERR), ">&=", $self->{stderr_copy}
         if $self->{stderr_copy};
      $task->();
   }
   else {
      warn "Lost cleanup task";
   }
   return;
}

sub _d {
   my ($package, undef, $line) = caller 0;
   @_ = map { (my $temp = $_) =~ s/\n/\n# /g; $temp; }
        map { defined $_ ? $_ : 'undef' }
        @_;
   print STDERR "# $package:$line $PID ", join(' ', @_), "\n";
}

1;
}
# ###########################################################################
# End CleanupTask package
# ###########################################################################

# ###########################################################################
# IndexLength package
# This package is a copy without comments from the original.  The original
# with comments and its test file can be found in the Bazaar repository at,
#   lib/IndexLength.pm
#   t/lib/IndexLength.t
# See https://launchpad.net/percona-toolkit for more information.
# ###########################################################################
{

package IndexLength;

use strict;
use warnings FATAL => 'all';
use English qw(-no_match_vars);
use constant PTDEBUG => $ENV{PTDEBUG} || 0;

use Data::Dumper;
use Carp;
$Data::Dumper::Indent    = 1;
$Data::Dumper::Sortkeys  = 1;
$Data::Dumper::Quotekeys = 0;

sub new {
   my ( $class, %args ) = @_;
   my @required_args = qw(Quoter);
   foreach my $arg ( @required_args ) {
      die "I need a $arg argument" unless $args{$arg};
   }

   my $self = {
       Quoter => $args{Quoter},
   };

   return bless $self, $class;
}

sub index_length {
   my ($self, %args) = @_;
   my @required_args = qw(Cxn tbl index);
   foreach my $arg ( @required_args ) {
      die "I need a $arg argument" unless $args{$arg};
   }
   my ($cxn) = @args{@required_args};

   die "The tbl argument does not have a tbl_struct"
      unless exists $args{tbl}->{tbl_struct};
   die "Index $args{index} does not exist in table $args{tbl}->{name}"
      unless $args{tbl}->{tbl_struct}->{keys}->{$args{index}};

   my $index_struct = $args{tbl}->{tbl_struct}->{keys}->{$args{index}};
   my $index_cols   = $index_struct->{cols};
   my $n_index_cols = $args{n_index_cols};
   if ( !$n_index_cols || $n_index_cols > @$index_cols ) {
      $n_index_cols = scalar @$index_cols;
   }

   my $vals = $self->_get_first_values(
      %args,
      n_index_cols => $n_index_cols,
   );

   my $sql = $self->_make_range_query(
      %args,
      n_index_cols => $n_index_cols,
      vals         => $vals,
   );
   my $sth = $cxn->dbh()->prepare($sql);
   PTDEBUG && _d($sth->{Statement}, 'params:', @$vals);
   $sth->execute(@$vals);
   my $row = $sth->fetchrow_hashref();
   $sth->finish();
   PTDEBUG && _d('Range scan:', Dumper($row));
   return $row->{key_len}, $row->{key};
}

sub _get_first_values {
   my ($self, %args) = @_;
   my @required_args = qw(Cxn tbl index n_index_cols);
   foreach my $arg ( @required_args ) {
      die "I need a $arg argument" unless $args{$arg};
   }
   my ($cxn, $tbl, $index, $n_index_cols) = @args{@required_args};

   my $q = $self->{Quoter};

   my $index_struct  = $tbl->{tbl_struct}->{keys}->{$index};
   my $index_cols    = $index_struct->{cols};
   my $index_columns;
   eval {
   $index_columns = join (', ',
      map { $q->quote($_) } @{$index_cols}[0..($n_index_cols - 1)]);
  };
  if ($EVAL_ERROR) {
      confess "$EVAL_ERROR";
  }



   my @where;
   foreach my $col ( @{$index_cols}[0..($n_index_cols - 1)] ) {
      push @where, $q->quote($col) . " IS NOT NULL"
   }

   my $sql = "SELECT /*!40001 SQL_NO_CACHE */ $index_columns "
           . "FROM $tbl->{name} FORCE INDEX (" . $q->quote($index) . ") "
           . "WHERE " . join(' AND ', @where)
           . " ORDER BY $index_columns "
           . "LIMIT 1 /*key_len*/";  # only need 1 row
   PTDEBUG && _d($sql);
   my $vals = $cxn->dbh()->selectrow_arrayref($sql);
   return $vals;
}

sub _make_range_query {
   my ($self, %args) = @_;
   my @required_args = qw(tbl index n_index_cols vals);
   foreach my $arg ( @required_args ) {
      die "I need a $arg argument" unless $args{$arg};
   }
   my ($tbl, $index, $n_index_cols, $vals) = @args{@required_args};

   my $q = $self->{Quoter};

   my $index_struct = $tbl->{tbl_struct}->{keys}->{$index};
   my $index_cols   = $index_struct->{cols};

   my @where;
   if ( $n_index_cols > 1 ) {
      foreach my $n ( 0..($n_index_cols - 2) ) {
         my $col = $index_cols->[$n];
         my $val = $tbl->{tbl_struct}->{type_for}->{$col} eq 'enum' ? "CAST(? AS UNSIGNED)" : "?";
         push @where, $q->quote($col) . " = " . $val;
      }
   }

   my $col = $index_cols->[$n_index_cols - 1];
   my $val = $vals->[-1];  # should only be as many vals as cols
   my $condition = $tbl->{tbl_struct}->{type_for}->{$col} eq 'enum' ? "CAST(? AS UNSIGNED)" : "?";
   push @where, $q->quote($col) . " >= " . $condition;

   my $sql = "EXPLAIN SELECT /*!40001 SQL_NO_CACHE */ * "
           . "FROM $tbl->{name} FORCE INDEX (" . $q->quote($index) . ") "
           . "WHERE " . join(' AND ', @where)
           . " /*key_len*/";
   return $sql;
}

sub _d {
   my ($package, undef, $line) = caller 0;
   @_ = map { (my $temp = $_) =~ s/\n/\n# /g; $temp; }
        map { defined $_ ? $_ : 'undef' }
        @_;
   print STDERR "# $package:$line $PID ", join(' ', @_), "\n";
}

1;
}
# ###########################################################################
# End IndexLength package
# ###########################################################################

# ###########################################################################
# HTTP::Micro package
# This package is a copy without comments from the original.  The original
# with comments and its test file can be found in the Bazaar repository at,
#   lib/HTTP/Micro.pm
#   t/lib/HTTP/Micro.t
# See https://launchpad.net/percona-toolkit for more information.
# ###########################################################################
{
package HTTP::Micro;

our $VERSION = '0.01';

use strict;
use warnings FATAL => 'all';
use English qw(-no_match_vars);
use Carp ();

my @attributes;
BEGIN {
    @attributes = qw(agent timeout);
    no strict 'refs';
    for my $accessor ( @attributes ) {
        *{$accessor} = sub {
            @_ > 1 ? $_[0]->{$accessor} = $_[1] : $_[0]->{$accessor};
        };
    }
}

sub new {
    my($class, %args) = @_;
    (my $agent = $class) =~ s{::}{-}g;
    my $self = {
        agent        => $agent . "/" . ($class->VERSION || 0),
        timeout      => 60,
    };
    for my $key ( @attributes ) {
        $self->{$key} = $args{$key} if exists $args{$key}
    }
    return bless $self, $class;
}

my %DefaultPort = (
    http => 80,
    https => 443,
);

sub request {
    my ($self, $method, $url, $args) = @_;
    @_ == 3 || (@_ == 4 && ref $args eq 'HASH')
      or Carp::croak(q/Usage: $http->request(METHOD, URL, [HASHREF])/);
    $args ||= {}; # we keep some state in this during _request

    my $response;
    for ( 0 .. 1 ) {
        $response = eval { $self->_request($method, $url, $args) };
        last unless $@ && $method eq 'GET'
            && $@ =~ m{^(?:Socket closed|Unexpected end)};
    }

    if (my $e = "$@") {
        $response = {
            success => q{},
            status  => 599,
            reason  => 'Internal Exception',
            content => $e,
            headers => {
                'content-type'   => 'text/plain',
                'content-length' => length $e,
            }
        };
    }
    return $response;
}

sub _request {
    my ($self, $method, $url, $args) = @_;

    my ($scheme, $host, $port, $path_query) = $self->_split_url($url);

    my $request = {
        method    => $method,
        scheme    => $scheme,
        host_port => ($port == $DefaultPort{$scheme} ? $host : "$host:$port"),
        uri       => $path_query,
        headers   => {},
    };

    my $handle  = HTTP::Micro::Handle->new(timeout => $self->{timeout});

    $handle->connect($scheme, $host, $port);

    $self->_prepare_headers_and_cb($request, $args);
    $handle->write_request_header(@{$request}{qw/method uri headers/});
    $handle->write_content_body($request) if $request->{content};

    my $response;
    do { $response = $handle->read_response_header }
        until (substr($response->{status},0,1) ne '1');

    if (!($method eq 'HEAD' || $response->{status} =~ /^[23]04/)) {
        $response->{content} = '';
        $handle->read_content_body(sub { $_[1]->{content} .= $_[0] }, $response);
    }

    $handle->close;
    $response->{success} = substr($response->{status},0,1) eq '2';
    return $response;
}

sub _prepare_headers_and_cb {
    my ($self, $request, $args) = @_;

    for ($args->{headers}) {
        next unless defined;
        while (my ($k, $v) = each %$_) {
            $request->{headers}{lc $k} = $v;
        }
    }
    $request->{headers}{'host'}         = $request->{host_port};
    $request->{headers}{'connection'}   = "close";
    $request->{headers}{'user-agent'} ||= $self->{agent};

    if (defined $args->{content}) {
        $request->{headers}{'content-type'} ||= "application/octet-stream";
        utf8::downgrade($args->{content}, 1)
            or Carp::croak(q/Wide character in request message body/);
        $request->{headers}{'content-length'} = length $args->{content};
        $request->{content} = $args->{content};
    }
    return;
}

sub _split_url {
    my $url = pop;

    my ($scheme, $authority, $path_query) = $url =~ m<\A([^:/?#]+)://([^/?#]*)([^#]*)>
      or Carp::croak(qq/Cannot parse URL: '$url'/);

    $scheme     = lc $scheme;
    $path_query = "/$path_query" unless $path_query =~ m<\A/>;

    my $host = (length($authority)) ? lc $authority : 'localhost';
       $host =~ s/\A[^@]*@//;   # userinfo
    my $port = do {
       $host =~ s/:([0-9]*)\z// && length $1
         ? $1
         : $DefaultPort{$scheme}
    };

    return ($scheme, $host, $port, $path_query);
}

} # HTTP::Micro

{
   package HTTP::Micro::Handle;

   use strict;
   use warnings FATAL => 'all';
   use English qw(-no_match_vars);

   use Carp       qw(croak);
   use Errno      qw(EINTR EPIPE);
   use IO::Socket qw(SOCK_STREAM);

   sub BUFSIZE () { 32768 }

   my $Printable = sub {
       local $_ = shift;
       s/\r/\\r/g;
       s/\n/\\n/g;
       s/\t/\\t/g;
       s/([^\x20-\x7E])/sprintf('\\x%.2X', ord($1))/ge;
       $_;
   };

   sub new {
       my ($class, %args) = @_;
       return bless {
           rbuf          => '',
           timeout       => 60,
           max_line_size => 16384,
           %args
       }, $class;
   }

   my $ssl_verify_args = {
       check_cn         => "when_only",
       wildcards_in_alt => "anywhere",
       wildcards_in_cn  => "anywhere"
   };

   sub connect {
       @_ == 4 || croak(q/Usage: $handle->connect(scheme, host, port)/);
       my ($self, $scheme, $host, $port) = @_;

       if ( $scheme eq 'https' ) {
           eval "require IO::Socket::SSL"
               unless exists $INC{'IO/Socket/SSL.pm'};
           croak(qq/IO::Socket::SSL must be installed for https support\n/)
               unless $INC{'IO/Socket/SSL.pm'};
       }
       elsif ( $scheme ne 'http' ) {
         croak(qq/Unsupported URL scheme '$scheme'\n/);
       }

       $self->{fh} = IO::Socket::INET->new(
           PeerHost  => $host,
           PeerPort  => $port,
           Proto     => 'tcp',
           Type      => SOCK_STREAM,
           Timeout   => $self->{timeout}
       ) or croak(qq/Could not connect to '$host:$port': $@/);

       binmode($self->{fh})
         or croak(qq/Could not binmode() socket: '$!'/);

       if ( $scheme eq 'https') {
           IO::Socket::SSL->start_SSL($self->{fh});
           ref($self->{fh}) eq 'IO::Socket::SSL'
               or die(qq/SSL connection failed for $host\n/);
           if ( $self->{fh}->can("verify_hostname") ) {
               $self->{fh}->verify_hostname( $host, $ssl_verify_args )
                  or die(qq/SSL certificate not valid for $host\n/);
           }
           else {
            my $fh = $self->{fh};
            _verify_hostname_of_cert($host, _peer_certificate($fh), $ssl_verify_args)
                  or die(qq/SSL certificate not valid for $host\n/);
            }
       }

       $self->{host} = $host;
       $self->{port} = $port;

       return $self;
   }

   sub close {
       @_ == 1 || croak(q/Usage: $handle->close()/);
       my ($self) = @_;
       CORE::close($self->{fh})
         or croak(qq/Could not close socket: '$!'/);
   }

   sub write {
       @_ == 2 || croak(q/Usage: $handle->write(buf)/);
       my ($self, $buf) = @_;

       my $len = length $buf;
       my $off = 0;

       local $SIG{PIPE} = 'IGNORE';

       while () {
           $self->can_write
             or croak(q/Timed out while waiting for socket to become ready for writing/);
           my $r = syswrite($self->{fh}, $buf, $len, $off);
           if (defined $r) {
               $len -= $r;
               $off += $r;
               last unless $len > 0;
           }
           elsif ($! == EPIPE) {
               croak(qq/Socket closed by remote server: $!/);
           }
           elsif ($! != EINTR) {
               croak(qq/Could not write to socket: '$!'/);
           }
       }
       return $off;
   }

   sub read {
       @_ == 2 || @_ == 3 || croak(q/Usage: $handle->read(len)/);
       my ($self, $len) = @_;

       my $buf  = '';
       my $got = length $self->{rbuf};

       if ($got) {
           my $take = ($got < $len) ? $got : $len;
           $buf  = substr($self->{rbuf}, 0, $take, '');
           $len -= $take;
       }

       while ($len > 0) {
           $self->can_read
             or croak(q/Timed out while waiting for socket to become ready for reading/);
           my $r = sysread($self->{fh}, $buf, $len, length $buf);
           if (defined $r) {
               last unless $r;
               $len -= $r;
           }
           elsif ($! != EINTR) {
               croak(qq/Could not read from socket: '$!'/);
           }
       }
       if ($len) {
           croak(q/Unexpected end of stream/);
       }
       return $buf;
   }

   sub readline {
       @_ == 1 || croak(q/Usage: $handle->readline()/);
       my ($self) = @_;

       while () {
           if ($self->{rbuf} =~ s/\A ([^\x0D\x0A]* \x0D?\x0A)//x) {
               return $1;
           }
           $self->can_read
             or croak(q/Timed out while waiting for socket to become ready for reading/);
           my $r = sysread($self->{fh}, $self->{rbuf}, BUFSIZE, length $self->{rbuf});
           if (defined $r) {
               last unless $r;
           }
           elsif ($! != EINTR) {
               croak(qq/Could not read from socket: '$!'/);
           }
       }
       croak(q/Unexpected end of stream while looking for line/);
   }

   sub read_header_lines {
       @_ == 1 || @_ == 2 || croak(q/Usage: $handle->read_header_lines([headers])/);
       my ($self, $headers) = @_;
       $headers ||= {};
       my $lines   = 0;
       my $val;

       while () {
            my $line = $self->readline;

            if ($line =~ /\A ([^\x00-\x1F\x7F:]+) : [\x09\x20]* ([^\x0D\x0A]*)/x) {
                my ($field_name) = lc $1;
                $val = \($headers->{$field_name} = $2);
            }
            elsif ($line =~ /\A [\x09\x20]+ ([^\x0D\x0A]*)/x) {
                $val
                  or croak(q/Unexpected header continuation line/);
                next unless length $1;
                $$val .= ' ' if length $$val;
                $$val .= $1;
            }
            elsif ($line =~ /\A \x0D?\x0A \z/x) {
               last;
            }
            else {
               croak(q/Malformed header line: / . $Printable->($line));
            }
       }
       return $headers;
   }

   sub write_header_lines {
       (@_ == 2 && ref $_[1] eq 'HASH') || croak(q/Usage: $handle->write_header_lines(headers)/);
       my($self, $headers) = @_;

       my $buf = '';
       while (my ($k, $v) = each %$headers) {
           my $field_name = lc $k;
            $field_name =~ /\A [\x21\x23-\x27\x2A\x2B\x2D\x2E\x30-\x39\x41-\x5A\x5E-\x7A\x7C\x7E]+ \z/x
               or croak(q/Invalid HTTP header field name: / . $Printable->($field_name));
            $field_name =~ s/\b(\w)/\u$1/g;
            $buf .= "$field_name: $v\x0D\x0A";
       }
       $buf .= "\x0D\x0A";
       return $self->write($buf);
   }

   sub read_content_body {
       @_ == 3 || @_ == 4 || croak(q/Usage: $handle->read_content_body(callback, response, [read_length])/);
       my ($self, $cb, $response, $len) = @_;
       $len ||= $response->{headers}{'content-length'};

       croak("No content-length in the returned response, and this "
           . "UA doesn't implement chunking") unless defined $len;

       while ($len > 0) {
           my $read = ($len > BUFSIZE) ? BUFSIZE : $len;
           $cb->($self->read($read), $response);
           $len -= $read;
       }

       return;
   }

   sub write_content_body {
       @_ == 2 || croak(q/Usage: $handle->write_content_body(request)/);
       my ($self, $request) = @_;
       my ($len, $content_length) = (0, $request->{headers}{'content-length'});

       $len += $self->write($request->{content});

       $len == $content_length
         or croak(qq/Content-Length missmatch (got: $len expected: $content_length)/);

       return $len;
   }

   sub read_response_header {
       @_ == 1 || croak(q/Usage: $handle->read_response_header()/);
       my ($self) = @_;

       my $line = $self->readline;

       $line =~ /\A (HTTP\/(0*\d+\.0*\d+)) [\x09\x20]+ ([0-9]{3}) [\x09\x20]+ ([^\x0D\x0A]*) \x0D?\x0A/x
         or croak(q/Malformed Status-Line: / . $Printable->($line));

       my ($protocol, $version, $status, $reason) = ($1, $2, $3, $4);

       return {
           status   => $status,
           reason   => $reason,
           headers  => $self->read_header_lines,
           protocol => $protocol,
       };
   }

   sub write_request_header {
       @_ == 4 || croak(q/Usage: $handle->write_request_header(method, request_uri, headers)/);
       my ($self, $method, $request_uri, $headers) = @_;

       return $self->write("$method $request_uri HTTP/1.1\x0D\x0A")
            + $self->write_header_lines($headers);
   }

   sub _do_timeout {
       my ($self, $type, $timeout) = @_;
       $timeout = $self->{timeout}
           unless defined $timeout && $timeout >= 0;

       my $fd = fileno $self->{fh};
       defined $fd && $fd >= 0
         or croak(q/select(2): 'Bad file descriptor'/);

       my $initial = time;
       my $pending = $timeout;
       my $nfound;

       vec(my $fdset = '', $fd, 1) = 1;

       while () {
           $nfound = ($type eq 'read')
               ? select($fdset, undef, undef, $pending)
               : select(undef, $fdset, undef, $pending) ;
           if ($nfound == -1) {
               $! == EINTR
                 or croak(qq/select(2): '$!'/);
               redo if !$timeout || ($pending = $timeout - (time - $initial)) > 0;
               $nfound = 0;
           }
           last;
       }
       $! = 0;
       return $nfound;
   }

   sub can_read {
       @_ == 1 || @_ == 2 || croak(q/Usage: $handle->can_read([timeout])/);
       my $self = shift;
       return $self->_do_timeout('read', @_)
   }

   sub can_write {
       @_ == 1 || @_ == 2 || croak(q/Usage: $handle->can_write([timeout])/);
       my $self = shift;
       return $self->_do_timeout('write', @_)
   }
}  # HTTP::Micro::Handle

my $prog = <<'EOP';
BEGIN {
   if ( defined &IO::Socket::SSL::CAN_IPV6 ) {
      *CAN_IPV6 = \*IO::Socket::SSL::CAN_IPV6;
   }
   else {
      constant->import( CAN_IPV6 => '' );
   }
   my %const = (
      NID_CommonName => 13,
      GEN_DNS => 2,
      GEN_IPADD => 7,
   );
   while ( my ($name,$value) = each %const ) {
      no strict 'refs';
      *{$name} = UNIVERSAL::can( 'Net::SSLeay', $name ) || sub { $value };
   }
}
{
   use Carp qw(croak);
   my %dispatcher = (
      issuer =>  sub { Net::SSLeay::X509_NAME_oneline( Net::SSLeay::X509_get_issuer_name( shift )) },
      subject => sub { Net::SSLeay::X509_NAME_oneline( Net::SSLeay::X509_get_subject_name( shift )) },
   );
   if ( $Net::SSLeay::VERSION >= 1.30 ) {
      $dispatcher{commonName} = sub {
         my $cn = Net::SSLeay::X509_NAME_get_text_by_NID(
            Net::SSLeay::X509_get_subject_name( shift ), NID_CommonName);
         $cn =~s{\0$}{}; # work around Bug in Net::SSLeay <1.33
         $cn;
      }
   } else {
      $dispatcher{commonName} = sub {
         croak "you need at least Net::SSLeay version 1.30 for getting commonName"
      }
   }

   if ( $Net::SSLeay::VERSION >= 1.33 ) {
      $dispatcher{subjectAltNames} = sub { Net::SSLeay::X509_get_subjectAltNames( shift ) };
   } else {
      $dispatcher{subjectAltNames} = sub {
         return;
      };
   }

   $dispatcher{authority} = $dispatcher{issuer};
   $dispatcher{owner}     = $dispatcher{subject};
   $dispatcher{cn}        = $dispatcher{commonName};

   sub _peer_certificate {
      my ($self, $field) = @_;
      my $ssl = $self->_get_ssl_object or return;

      my $cert = ${*$self}{_SSL_certificate}
         ||= Net::SSLeay::get_peer_certificate($ssl)
         or return $self->error("Could not retrieve peer certificate");

      if ($field) {
         my $sub = $dispatcher{$field} or croak
            "invalid argument for peer_certificate, valid are: ".join( " ",keys %dispatcher ).
            "\nMaybe you need to upgrade your Net::SSLeay";
         return $sub->($cert);
      } else {
         return $cert
      }
   }


   my %scheme = (
      ldap => {
         wildcards_in_cn    => 0,
         wildcards_in_alt => 'leftmost',
         check_cn         => 'always',
      },
      http => {
         wildcards_in_cn    => 'anywhere',
         wildcards_in_alt => 'anywhere',
         check_cn         => 'when_only',
      },
      smtp => {
         wildcards_in_cn    => 0,
         wildcards_in_alt => 0,
         check_cn         => 'always'
      },
      none => {}, # do not check
   );

   $scheme{www}  = $scheme{http}; # alias
   $scheme{xmpp} = $scheme{http}; # rfc 3920
   $scheme{pop3} = $scheme{ldap}; # rfc 2595
   $scheme{imap} = $scheme{ldap}; # rfc 2595
   $scheme{acap} = $scheme{ldap}; # rfc 2595
   $scheme{nntp} = $scheme{ldap}; # rfc 4642
   $scheme{ftp}  = $scheme{http}; # rfc 4217


   sub _verify_hostname_of_cert {
      my $identity = shift;
      my $cert = shift;
      my $scheme = shift || 'none';
      if ( ! ref($scheme) ) {
         $scheme = $scheme{$scheme} or croak "scheme $scheme not defined";
      }

      return 1 if ! %$scheme; # 'none'

      my $commonName = $dispatcher{cn}->($cert);
      my @altNames   = $dispatcher{subjectAltNames}->($cert);

      if ( my $sub = $scheme->{callback} ) {
         return $sub->($identity,$commonName,@altNames);
      }


      my $ipn;
      if ( CAN_IPV6 and $identity =~m{:} ) {
         $ipn = IO::Socket::SSL::inet_pton(IO::Socket::SSL::AF_INET6,$identity)
            or croak "'$identity' is not IPv6, but neither IPv4 nor hostname";
      } elsif ( $identity =~m{^\d+\.\d+\.\d+\.\d+$} ) {
         $ipn = IO::Socket::SSL::inet_aton( $identity ) or croak "'$identity' is not IPv4, but neither IPv6 nor hostname";
      } else {
         if ( $identity =~m{[^a-zA-Z0-9_.\-]} ) {
            $identity =~m{\0} and croak("name '$identity' has \\0 byte");
            $identity = IO::Socket::SSL::idn_to_ascii($identity) or
               croak "Warning: Given name '$identity' could not be converted to IDNA!";
         }
      }

      my $check_name = sub {
         my ($name,$identity,$wtyp) = @_;
         $wtyp ||= '';
         my $pattern;
         if ( $wtyp eq 'anywhere' and $name =~m{^([a-zA-Z0-9_\-]*)\*(.+)} ) {
            $pattern = qr{^\Q$1\E[a-zA-Z0-9_\-]*\Q$2\E$}i;
         } elsif ( $wtyp eq 'leftmost' and $name =~m{^\*(\..+)$} ) {
            $pattern = qr{^[a-zA-Z0-9_\-]*\Q$1\E$}i;
         } else {
            $pattern = qr{^\Q$name\E$}i;
         }
         return $identity =~ $pattern;
      };

      my $alt_dnsNames = 0;
      while (@altNames) {
         my ($type, $name) = splice (@altNames, 0, 2);
         if ( $ipn and $type == GEN_IPADD ) {
            return 1 if $ipn eq $name;

         } elsif ( ! $ipn and $type == GEN_DNS ) {
            $name =~s/\s+$//; $name =~s/^\s+//;
            $alt_dnsNames++;
            $check_name->($name,$identity,$scheme->{wildcards_in_alt})
               and return 1;
         }
      }

      if ( ! $ipn and (
         $scheme->{check_cn} eq 'always' or
         $scheme->{check_cn} eq 'when_only' and !$alt_dnsNames)) {
         $check_name->($commonName,$identity,$scheme->{wildcards_in_cn})
            and return 1;
      }

      return 0; # no match
   }
}
EOP

eval { require IO::Socket::SSL };
if ( $INC{"IO/Socket/SSL.pm"} ) {
   eval $prog;
   die $@ if $@;
}

1;
# ###########################################################################
# End HTTP::Micro package
# ###########################################################################

# ###########################################################################
# VersionCheck package
# This package is a copy without comments from the original.  The original
# with comments and its test file can be found in the Bazaar repository at,
#   lib/VersionCheck.pm
#   t/lib/VersionCheck.t
# See https://launchpad.net/percona-toolkit for more information.
# ###########################################################################
{
package VersionCheck;


use strict;
use warnings FATAL => 'all';
use English qw(-no_match_vars);

use constant PTDEBUG => $ENV{PTDEBUG} || 0;

use Data::Dumper;
local $Data::Dumper::Indent    = 1;
local $Data::Dumper::Sortkeys  = 1;
local $Data::Dumper::Quotekeys = 0;

use Digest::MD5 qw(md5_hex);
use Sys::Hostname qw(hostname);
use File::Basename qw();
use File::Spec;
use FindBin qw();

eval {
   require Percona::Toolkit;
   require HTTP::Micro;
};

my $home    = $ENV{HOME} || $ENV{HOMEPATH} || $ENV{USERPROFILE} || '.';
my @vc_dirs = (
   '/etc/percona',
   '/etc/percona-toolkit',
   '/tmp',
   "$home",
);

{
   my $file    = 'percona-version-check';

   sub version_check_file {
      foreach my $dir ( @vc_dirs ) {
         if ( -d $dir && -w $dir ) {
            PTDEBUG && _d('Version check file', $file, 'in', $dir);
            return $dir . '/' . $file;
         }
      }
      PTDEBUG && _d('Version check file', $file, 'in', $ENV{PWD});
      return $file;  # in the CWD
   }
}

sub version_check_time_limit {
   return 60 * 60 * 24;  # one day
}


sub version_check {
   my (%args) = @_;

   my $instances = $args{instances} || [];
   my $instances_to_check;

   PTDEBUG && _d('FindBin::Bin:', $FindBin::Bin);
   if ( !$args{force} ) {
      if ( $FindBin::Bin
           && (-d "$FindBin::Bin/../.bzr"    ||
               -d "$FindBin::Bin/../../.bzr" ||
               -d "$FindBin::Bin/../.git"    ||
               -d "$FindBin::Bin/../../.git"
              )
         ) {
         PTDEBUG && _d("$FindBin::Bin/../.bzr disables --version-check");
         return;
      }
   }

   eval {
      foreach my $instance ( @$instances ) {
         my ($name, $id) = get_instance_id($instance);
         $instance->{name} = $name;
         $instance->{id}   = $id;
      }

      push @$instances, { name => 'system', id => 0 };

      $instances_to_check = get_instances_to_check(
         instances => $instances,
         vc_file   => $args{vc_file},  # testing
         now       => $args{now},      # testing
      );
      PTDEBUG && _d(scalar @$instances_to_check, 'instances to check');
      return unless @$instances_to_check;

      my $protocol = 'https';
      eval { require IO::Socket::SSL; };
      if ( $EVAL_ERROR ) {
         PTDEBUG && _d($EVAL_ERROR);
         PTDEBUG && _d("SSL not available, won't run version_check");
         return;
      }
      PTDEBUG && _d('Using', $protocol);

      my $advice = pingback(
         instances => $instances_to_check,
         protocol  => $protocol,
         url       => $args{url}                       # testing
                   || $ENV{PERCONA_VERSION_CHECK_URL}  # testing
                   || "$protocol://v.percona.com",
      );
      if ( $advice ) {
         PTDEBUG && _d('Advice:', Dumper($advice));
         if ( scalar @$advice > 1) {
            print "\n# " . scalar @$advice . " software updates are "
               . "available:\n";
         }
         else {
            print "\n# A software update is available:\n";
         }
         print join("\n", map { "#   * $_" } @$advice), "\n\n";
      }
   };
   if ( $EVAL_ERROR ) {
      PTDEBUG && _d('Version check failed:', $EVAL_ERROR);
   }

   if ( @$instances_to_check ) {
      eval {
         update_check_times(
            instances => $instances_to_check,
            vc_file   => $args{vc_file},  # testing
            now       => $args{now},      # testing
         );
      };
      if ( $EVAL_ERROR ) {
         PTDEBUG && _d('Error updating version check file:', $EVAL_ERROR);
      }
   }

   if ( $ENV{PTDEBUG_VERSION_CHECK} ) {
      warn "Exiting because the PTDEBUG_VERSION_CHECK "
         . "environment variable is defined.\n";
      exit 255;
   }

   return;
}

sub get_instances_to_check {
   my (%args) = @_;

   my $instances = $args{instances};
   my $now       = $args{now}     || int(time);
   my $vc_file   = $args{vc_file} || version_check_file();

   if ( !-f $vc_file ) {
      PTDEBUG && _d('Version check file', $vc_file, 'does not exist;',
         'version checking all instances');
      return $instances;
   }

   open my $fh, '<', $vc_file or die "Cannot open $vc_file: $OS_ERROR";
   chomp(my $file_contents = do { local $/ = undef; <$fh> });
   PTDEBUG && _d('Version check file', $vc_file, 'contents:', $file_contents);
   close $fh;
   my %last_check_time_for = $file_contents =~ /^([^,]+),(.+)$/mg;

   my $check_time_limit = version_check_time_limit();
   my @instances_to_check;
   foreach my $instance ( @$instances ) {
      my $last_check_time = $last_check_time_for{ $instance->{id} };
      PTDEBUG && _d('Instance', $instance->{id}, 'last checked',
         $last_check_time, 'now', $now, 'diff', $now - ($last_check_time || 0),
         'hours until next check',
         sprintf '%.2f',
            ($check_time_limit - ($now - ($last_check_time || 0))) / 3600);
      if ( !defined $last_check_time
           || ($now - $last_check_time) >= $check_time_limit ) {
         PTDEBUG && _d('Time to check', Dumper($instance));
         push @instances_to_check, $instance;
      }
   }

   return \@instances_to_check;
}

sub update_check_times {
   my (%args) = @_;

   my $instances = $args{instances};
   my $now       = $args{now}     || int(time);
   my $vc_file   = $args{vc_file} || version_check_file();
   PTDEBUG && _d('Updating last check time:', $now);

   my %all_instances = map {
      $_->{id} => { name => $_->{name}, ts => $now }
   } @$instances;

   if ( -f $vc_file ) {
      open my $fh, '<', $vc_file or die "Cannot read $vc_file: $OS_ERROR";
      my $contents = do { local $/ = undef; <$fh> };
      close $fh;

      foreach my $line ( split("\n", ($contents || '')) ) {
         my ($id, $ts) = split(',', $line);
         if ( !exists $all_instances{$id} ) {
            $all_instances{$id} = { ts => $ts };  # original ts, not updated
         }
      }
   }

   open my $fh, '>', $vc_file or die "Cannot write to $vc_file: $OS_ERROR";
   foreach my $id ( sort keys %all_instances ) {
      PTDEBUG && _d('Updated:', $id, Dumper($all_instances{$id}));
      print { $fh } $id . ',' . $all_instances{$id}->{ts} . "\n";
   }
   close $fh;

   return;
}

sub get_instance_id {
   my ($instance) = @_;

   my $dbh = $instance->{dbh};
   my $dsn = $instance->{dsn};

   my $sql = q{SELECT CONCAT(@@hostname, @@port)};
   PTDEBUG && _d($sql);
   my ($name) = eval { $dbh->selectrow_array($sql) };
   if ( $EVAL_ERROR ) {
      PTDEBUG && _d($EVAL_ERROR);
      $sql = q{SELECT @@hostname};
      PTDEBUG && _d($sql);
      ($name) = eval { $dbh->selectrow_array($sql) };
      if ( $EVAL_ERROR ) {
         PTDEBUG && _d($EVAL_ERROR);
         $name = ($dsn->{h} || 'localhost') . ($dsn->{P} || 3306);
      }
      else {
         $sql = q{SHOW VARIABLES LIKE 'port'};
         PTDEBUG && _d($sql);
         my (undef, $port) = eval { $dbh->selectrow_array($sql) };
         PTDEBUG && _d('port:', $port);
         $name .= $port || '';
      }
   }
   my $id = md5_hex($name);

   PTDEBUG && _d('MySQL instance:', $id, $name, Dumper($dsn));

   return $name, $id;
}


sub get_uuid {
    my $uuid_file = '/.percona-toolkit.uuid';
    foreach my $dir (@vc_dirs) {
        my $filename = $dir.$uuid_file;
        my $uuid=_read_uuid($filename);
        return $uuid if $uuid;
    }

    my $filename = $ENV{"HOME"} . $uuid_file;
    my $uuid = _generate_uuid();

    open(my $fh, '>', $filename) or die "Could not open file '$filename' $!";
    print $fh $uuid;
    close $fh;

    return $uuid;
}

sub _generate_uuid {
    return sprintf+($}="%04x")."$}-$}-$}-$}-".$}x3,map rand 65537,0..7;
}

sub _read_uuid {
    my $filename = shift;
    my $fh;

    eval {
        open($fh, '<:encoding(UTF-8)', $filename);
    };
    return if ($EVAL_ERROR);

    my $uuid;
    eval { $uuid = <$fh>; };
    return if ($EVAL_ERROR);

    chomp $uuid;
    return $uuid;
}


sub pingback {
   my (%args) = @_;
   my @required_args = qw(url instances);
   foreach my $arg ( @required_args ) {
      die "I need a $arg arugment" unless $args{$arg};
   }
   my $url       = $args{url};
   my $instances = $args{instances};

   my $ua = $args{ua} || HTTP::Micro->new( timeout => 3 );

   my $response = $ua->request('GET', $url);
   PTDEBUG && _d('Server response:', Dumper($response));
   die "No response from GET $url"
      if !$response;
   die("GET on $url returned HTTP status $response->{status}; expected 200\n",
       ($response->{content} || '')) if $response->{status} != 200;
   die("GET on $url did not return any programs to check")
      if !$response->{content};

   my $items = parse_server_response(
      response => $response->{content}
   );
   die "Failed to parse server requested programs: $response->{content}"
      if !scalar keys %$items;

   my $versions = get_versions(
      items     => $items,
      instances => $instances,
   );
   die "Failed to get any program versions; should have at least gotten Perl"
      if !scalar keys %$versions;

   my $client_content = encode_client_response(
      items      => $items,
      versions   => $versions,
      general_id => get_uuid(),
   );

   my $client_response = {
      headers => { "X-Percona-Toolkit-Tool" => File::Basename::basename($0) },
      content => $client_content,
   };
   PTDEBUG && _d('Client response:', Dumper($client_response));

   $response = $ua->request('POST', $url, $client_response);
   PTDEBUG && _d('Server suggestions:', Dumper($response));
   die "No response from POST $url $client_response"
      if !$response;
   die "POST $url returned HTTP status $response->{status}; expected 200"
      if $response->{status} != 200;

   return unless $response->{content};

   $items = parse_server_response(
      response   => $response->{content},
      split_vars => 0,
   );
   die "Failed to parse server suggestions: $response->{content}"
      if !scalar keys %$items;
   my @suggestions = map { $_->{vars} }
                     sort { $a->{item} cmp $b->{item} }
                     values %$items;

   return \@suggestions;
}

sub encode_client_response {
   my (%args) = @_;
   my @required_args = qw(items versions general_id);
   foreach my $arg ( @required_args ) {
      die "I need a $arg arugment" unless $args{$arg};
   }
   my ($items, $versions, $general_id) = @args{@required_args};

   my @lines;
   foreach my $item ( sort keys %$items ) {
      next unless exists $versions->{$item};
      if ( ref($versions->{$item}) eq 'HASH' ) {
         my $mysql_versions = $versions->{$item};
         for my $id ( sort keys %$mysql_versions ) {
            push @lines, join(';', $id, $item, $mysql_versions->{$id});
         }
      }
      else {
         push @lines, join(';', $general_id, $item, $versions->{$item});
      }
   }

   my $client_response = join("\n", @lines) . "\n";
   return $client_response;
}

sub parse_server_response {
   my (%args) = @_;
   my @required_args = qw(response);
   foreach my $arg ( @required_args ) {
      die "I need a $arg arugment" unless $args{$arg};
   }
   my ($response) = @args{@required_args};

   my %items = map {
      my ($item, $type, $vars) = split(";", $_);
      if ( !defined $args{split_vars} || $args{split_vars} ) {
         $vars = [ split(",", ($vars || '')) ];
      }
      $item => {
         item => $item,
         type => $type,
         vars => $vars,
      };
   } split("\n", $response);

   PTDEBUG && _d('Items:', Dumper(\%items));

   return \%items;
}

my %sub_for_type = (
   os_version          => \&get_os_version,
   perl_version        => \&get_perl_version,
   perl_module_version => \&get_perl_module_version,
   mysql_variable      => \&get_mysql_variable,
);

sub valid_item {
   my ($item) = @_;
   return unless $item;
   if ( !exists $sub_for_type{ $item->{type} } ) {
      PTDEBUG && _d('Invalid type:', $item->{type});
      return 0;
   }
   return 1;
}

sub get_versions {
   my (%args) = @_;
   my @required_args = qw(items);
   foreach my $arg ( @required_args ) {
      die "I need a $arg arugment" unless $args{$arg};
   }
   my ($items) = @args{@required_args};

   my %versions;
   foreach my $item ( values %$items ) {
      next unless valid_item($item);
      eval {
         my $version = $sub_for_type{ $item->{type} }->(
            item      => $item,
            instances => $args{instances},
         );
         if ( $version ) {
            chomp $version unless ref($version);
            $versions{$item->{item}} = $version;
         }
      };
      if ( $EVAL_ERROR ) {
         PTDEBUG && _d('Error getting version for', Dumper($item), $EVAL_ERROR);
      }
   }

   return \%versions;
}


sub get_os_version {
   if ( $OSNAME eq 'MSWin32' ) {
      require Win32;
      return Win32::GetOSDisplayName();
   }

  chomp(my $platform = `uname -s`);
  PTDEBUG && _d('platform:', $platform);
  return $OSNAME unless $platform;

   chomp(my $lsb_release
            = `which lsb_release 2>/dev/null | awk '{print \$1}'` || '');
   PTDEBUG && _d('lsb_release:', $lsb_release);

   my $release = "";

   if ( $platform eq 'Linux' ) {
      if ( -f "/etc/fedora-release" ) {
         $release = `cat /etc/fedora-release`;
      }
      elsif ( -f "/etc/redhat-release" ) {
         $release = `cat /etc/redhat-release`;
      }
      elsif ( -f "/etc/system-release" ) {
         $release = `cat /etc/system-release`;
      }
      elsif ( $lsb_release ) {
         $release = `$lsb_release -ds`;
      }
      elsif ( -f "/etc/lsb-release" ) {
         $release = `grep DISTRIB_DESCRIPTION /etc/lsb-release`;
         $release =~ s/^\w+="([^"]+)".+/$1/;
      }
      elsif ( -f "/etc/debian_version" ) {
         chomp(my $rel = `cat /etc/debian_version`);
         $release = "Debian $rel";
         if ( -f "/etc/apt/sources.list" ) {
             chomp(my $code_name = `awk '/^deb/ {print \$3}' /etc/apt/sources.list | awk -F/ '{print \$1}'| awk 'BEGIN {FS="|"} {print \$1}' | sort | uniq -c | sort -rn | head -n1 | awk '{print \$2}'`);
             $release .= " ($code_name)" if $code_name;
         }
      }
      elsif ( -f "/etc/os-release" ) { # openSUSE
         chomp($release = `grep PRETTY_NAME /etc/os-release`);
         $release =~ s/^PRETTY_NAME="(.+)"$/$1/;
      }
      elsif ( `ls /etc/*release 2>/dev/null` ) {
         if ( `grep DISTRIB_DESCRIPTION /etc/*release 2>/dev/null` ) {
            $release = `grep DISTRIB_DESCRIPTION /etc/*release | head -n1`;
         }
         else {
            $release = `cat /etc/*release | head -n1`;
         }
      }
   }
   elsif ( $platform =~ m/(?:BSD|^Darwin)$/ ) {
      my $rel = `uname -r`;
      $release = "$platform $rel";
   }
   elsif ( $platform eq "SunOS" ) {
      my $rel = `head -n1 /etc/release` || `uname -r`;
      $release = "$platform $rel";
   }

   if ( !$release ) {
      PTDEBUG && _d('Failed to get the release, using platform');
      $release = $platform;
   }
   chomp($release);

   $release =~ s/^"|"$//g;

   PTDEBUG && _d('OS version =', $release);
   return $release;
}

sub get_perl_version {
   my (%args) = @_;
   my $item = $args{item};
   return unless $item;

   my $version = sprintf '%vd', $PERL_VERSION;
   PTDEBUG && _d('Perl version', $version);
   return $version;
}

sub get_perl_module_version {
   my (%args) = @_;
   my $item = $args{item};
   return unless $item;

   my $var     = '$' . $item->{item} . '::VERSION';
   my $version = eval "use $item->{item}; $var;";
   PTDEBUG && _d('Perl version for', $var, '=', $version);
   return $version;
}

sub get_mysql_variable {
   return get_from_mysql(
      show => 'VARIABLES',
      @_,
   );
}

sub get_from_mysql {
   my (%args) = @_;
   my $show      = $args{show};
   my $item      = $args{item};
   my $instances = $args{instances};
   return unless $show && $item;

   if ( !$instances || !@$instances ) {
      PTDEBUG && _d('Cannot check', $item,
         'because there are no MySQL instances');
      return;
   }

   if ($item->{item} eq 'MySQL' && $item->{type} eq 'mysql_variable') {
      @{$item->{vars}} = grep { $_ eq 'version' || $_ eq 'version_comment' } @{$item->{vars}};
   }


   my @versions;
   my %version_for;
   foreach my $instance ( @$instances ) {
      next unless $instance->{id};  # special system instance has id=0
      my $dbh = $instance->{dbh};
      local $dbh->{FetchHashKeyName} = 'NAME_lc';
      my $sql = qq/SHOW $show/;
      PTDEBUG && _d($sql);
      my $rows = $dbh->selectall_hashref($sql, 'variable_name');

      my @versions;
      foreach my $var ( @{$item->{vars}} ) {
         $var = lc($var);
         my $version = $rows->{$var}->{value};
         PTDEBUG && _d('MySQL version for', $item->{item}, '=', $version,
            'on', $instance->{name});
         push @versions, $version;
      }
      $version_for{ $instance->{id} } = join(' ', @versions);
   }

   return \%version_for;
}

sub _d {
   my ($package, undef, $line) = caller 0;
   @_ = map { (my $temp = $_) =~ s/\n/\n# /g; $temp; }
        map { defined $_ ? $_ : 'undef' }
        @_;
   print STDERR "# $package:$line $PID ", join(' ', @_), "\n";
}

1;
}
# ###########################################################################
# End VersionCheck package
# ###########################################################################

# ###########################################################################
# Percona::XtraDB::Cluster package
# This package is a copy without comments from the original.  The original
# with comments and its test file can be found in the Bazaar repository at,
#   lib/Percona/XtraDB/Cluster.pm
#   t/lib/Percona/XtraDB/Cluster.t
# See https://launchpad.net/percona-toolkit for more information.
# ###########################################################################
{
package Percona::XtraDB::Cluster;

use strict;
use warnings FATAL => 'all';
use English qw(-no_match_vars);
use constant PTDEBUG => $ENV{PTDEBUG} || 0;

use Lmo;
use Data::Dumper;

{ local $EVAL_ERROR; eval { require Cxn } };

sub get_cluster_name {
   my ($self, $cxn) = @_;
   my $sql = "SHOW VARIABLES LIKE 'wsrep\_cluster\_name'";
   PTDEBUG && _d($cxn->name, $sql);
   my (undef, $cluster_name) = $cxn->dbh->selectrow_array($sql);
   return $cluster_name;
}

sub is_cluster_node {
   my ($self, $cxn) = @_;

   my $sql = "SHOW VARIABLES LIKE 'wsrep\_on'";
   PTDEBUG && _d($cxn->name, $sql);
   my $row = $cxn->dbh->selectrow_arrayref($sql);
   PTDEBUG && _d(Dumper($row));
   return unless $row && $row->[1] && ($row->[1] eq 'ON' || $row->[1] eq '1');

   my $cluster_name = $self->get_cluster_name($cxn);
   return $cluster_name;
}

sub same_node {
   my ($self, $cxn1, $cxn2) = @_;

   foreach my $val ('wsrep\_sst\_receive\_address', 'wsrep\_node\_name', 'wsrep\_node\_address') {
      my $sql = "SHOW VARIABLES LIKE '$val'";
      PTDEBUG && _d($cxn1->name, $cxn2->name, $sql);
      my (undef, $val1) = $cxn1->dbh->selectrow_array($sql);
      my (undef, $val2) = $cxn2->dbh->selectrow_array($sql);

      return unless ($val1 || '') eq ($val2 || '');
   }

   return 1;
}

sub find_cluster_nodes {
   my ($self, %args) = @_;

   my $dbh = $args{dbh};
   my $dsn = $args{dsn};
   my $dp  = $args{DSNParser};
   my $make_cxn = $args{make_cxn};


   my $sql = q{SHOW STATUS LIKE 'wsrep\_incoming\_addresses'};
   PTDEBUG && _d($sql);
   my (undef, $addresses) = $dbh->selectrow_array($sql);
   PTDEBUG && _d("Cluster nodes found: ", $addresses);
   return unless $addresses;

   my @addresses = grep { !/\Aunspecified\z/i }
                   split /,\s*/, $addresses;

   my @nodes;
   foreach my $address ( @addresses ) {
      my ($host, $port) = split /:/, $address;
      my $spec = "h=$host"
               . ($port ? ",P=$port" : "");
      my $node_dsn = $dp->parse($spec, $dsn);
      my $node_dbh = eval { $dp->get_dbh(
            $dp->get_cxn_params($node_dsn), { AutoCommit => 1 }) };
      if ( $EVAL_ERROR ) {
         print STDERR "Cannot connect to ", $dp->as_string($node_dsn),
                      ", discovered through $sql: $EVAL_ERROR\n";
         if ( !$port && $dsn->{P} != 3306 ) {
            $address .= ":3306";
            redo;
         }
         next;
      }
      PTDEBUG && _d('Connected to', $dp->as_string($node_dsn));
      $node_dbh->disconnect();

      push @nodes, $make_cxn->(dsn => $node_dsn);
   }

   return \@nodes;
}

sub remove_duplicate_cxns {
   my ($self, %args) = @_;
   my @cxns     = @{$args{cxns}};
   my $seen_ids = $args{seen_ids} || {};
   PTDEBUG && _d("Removing duplicates nodes from ", join(" ", map { $_->name } @cxns));
   my @trimmed_cxns;

   for my $cxn ( @cxns ) {
      my $id = $cxn->get_id();
      PTDEBUG && _d('Server ID for ', $cxn->name, ': ', $id);

      if ( ! $seen_ids->{$id}++ ) {
         push @trimmed_cxns, $cxn
      }
      else {
         PTDEBUG && _d("Removing ", $cxn->name,
                       ", ID ", $id, ", because we've already seen it");
      }
   }
   return \@trimmed_cxns;
}

sub same_cluster {
   my ($self, $cxn1, $cxn2) = @_;

   return 0 if !$self->is_cluster_node($cxn1) || !$self->is_cluster_node($cxn2);

   my $cluster1 = $self->get_cluster_name($cxn1);
   my $cluster2 = $self->get_cluster_name($cxn2);

   return ($cluster1 || '') eq ($cluster2 || '');
}

sub autodetect_nodes {
   my ($self, %args) = @_;
   my $ms       = $args{MasterSlave};
   my $dp       = $args{DSNParser};
   my $make_cxn = $args{make_cxn};
   my $nodes    = $args{nodes};
   my $seen_ids = $args{seen_ids};

   my $new_nodes = [];

   return $new_nodes unless @$nodes;

   for my $node ( @$nodes ) {
      my $nodes_found = $self->find_cluster_nodes(
         dbh       => $node->dbh(),
         dsn       => $node->dsn(),
         make_cxn  => $make_cxn,
         DSNParser => $dp,
      );
      push @$new_nodes, @$nodes_found;
   }

   $new_nodes = $self->remove_duplicate_cxns(
      cxns     => $new_nodes,
      seen_ids => $seen_ids
   );

   my $new_slaves = [];
   foreach my $node (@$new_nodes) {
      my $node_slaves = $ms->get_slaves(
         dbh      => $node->dbh(),
         dsn      => $node->dsn(),
         make_cxn => $make_cxn,
      );
      push @$new_slaves, @$node_slaves;
   }

   $new_slaves = $self->remove_duplicate_cxns(
      cxns     => $new_slaves,
      seen_ids => $seen_ids
   );

   my @new_slave_nodes = grep { $self->is_cluster_node($_) } @$new_slaves;

   my $slaves_of_slaves = $self->autodetect_nodes(
         %args,
         nodes => \@new_slave_nodes,
   );

   my @autodetected_nodes = ( @$new_nodes, @$new_slaves, @$slaves_of_slaves );
   return \@autodetected_nodes;
}

sub _d {
   my ($package, undef, $line) = caller 0;
   @_ = map { (my $temp = $_) =~ s/\n/\n# /g; $temp; }
        map { defined $_ ? $_ : 'undef' }
        @_;
   print STDERR "# $package:$line $PID ", join(' ', @_), "\n";
}

1;
}
# ###########################################################################
# End Percona::XtraDB::Cluster package
# ###########################################################################


# ###########################################################################
# This is a combination of modules and programs in one -- a runnable module.
# http://www.perl.com/pub/a/2006/07/13/lightning-articles.html?page=last
# Or, look it up in the Camel book on pages 642 and 643 in the 3rd edition.
#
# Check at the end of this package for the call to main() which actually runs
# the program.
# ###########################################################################
package pt_online_schema_change;

use strict;
use warnings FATAL => 'all';
use utf8;
use English qw(-no_match_vars);

use Percona::Toolkit;
use constant PTDEBUG => $ENV{PTDEBUG} || 0;

use List::Util qw(max);
use Time::HiRes qw(time sleep);
use Data::Dumper;
use VersionCompare;
$Data::Dumper::Indent    = 1;
$Data::Dumper::Sortkeys  = 1;
$Data::Dumper::Quotekeys = 0;

# Import Term::Readkey if available
# Not critical so don't fail if it's not
my $term_readkey = eval {
  require Term::ReadKey;
  Term::ReadKey->import();
  1;
};

use sigtrap 'handler', \&sig_int, 'normal-signals';


my $exit_status = 0;
my $oktorun     = 1;
my $dont_interrupt_now = 0;
my @drop_trigger_sqls;
my @triggers_not_dropped;
my $pxc_version = '0';
my $can_drop_triggers = 1;

my $triggers_info = [];

# Completely ignore these error codes.
my %ignore_code = (
   # Error: 1592 SQLSTATE: HY000  (ER_BINLOG_UNSAFE_STATEMENT)
   # Message: Statement may not be safe to log in statement format.
   # Ignore this warning because we have purposely set statement-based
   # replication.
   1592 => 1,
   # Error: 1062 SQLSTATE: 23000 ( ER_DUP_ENTRY )
   # Message: Duplicate entry '%ld' for key '%s'
   # MariaDB 5.5.28+ has this as a warning; See https://bugs.launchpad.net/percona-toolkit/+bug/1099836
   1062 => 1,
);

$OUTPUT_AUTOFLUSH = 1;

use constant {
   INVALID_PARAMETERS              => 1,
   UNSUPORTED_MYSQL_VERSION        => 2,
   NO_MINIMUM_REQUIREMENTS         => 3,
   NO_PRIMARY_OR_UNIQUE_KEY        => 4,
   INVALID_PLUGIN_FILE             => 5,
   INVALID_ALTER_FK_METHOD         => 6,
   INVALID_KEY_SIZE                => 7,
   CANNOT_DETERMINE_KEY_SIZE       => 9,
   NOT_SAFE_TO_ASCEND              => 9,
   ERROR_CREATING_NEW_TABLE        => 10,
   ERROR_ALTERING_TABLE            => 11,
   ERROR_CREATING_TRIGGERS         => 12,
   ERROR_RESTORING_TRIGGERS        => 13,
   ERROR_SWAPPING_TABLES           => 14,
   ERROR_UPDATING_FKS              => 15,
   ERROR_DROPPING_OLD_TABLE        => 16,
   UNSUPORTED_OPERATION            => 17,
   MYSQL_CONNECTION_ERROR          => 18,
   LOST_MYSQL_CONNECTION           => 19,
   ERROR_CREATING_REVERSE_TRIGGERS => 20,
};

sub _die {
   my ($msg, $exit_status) = @_;
   $exit_status ||= 255;
   chomp ($msg);
   print "$msg\n";
   exit $exit_status;
}

sub main {
   local @ARGV = @_;

   # Reset global vars else tests will fail.
   $exit_status          = 0;
   $oktorun              = 1;
   @drop_trigger_sqls    = ();
   @triggers_not_dropped = ();
   $dont_interrupt_now   = 0;
   %ignore_code = (1592 => 1, 1062 => 1, 1300 => 1);

   my %stats = (
      INSERT => 0,
   );

   # ########################################################################
   # Get configuration information.
   # ########################################################################
   my $q = new Quoter();
   my $o = new OptionParser();
   $o->get_specs();
   $o->get_opts();

   if ( $o->get('null-to-not-null') ) {
      $ignore_code{1048} = 1;
   }

   my $dp = $o->DSNParser();
   $dp->prop('set-vars', $o->set_vars());

   # The original table, i.e. the one being altered, must be specified
   # on the command line via the DSN.
   my ($db, $tbl);
   my $dsn = shift @ARGV;
   if ( !$dsn ) {
      $o->save_error('A DSN must be specified');
   }
   else {
      # Parse DSN string and convert it to a DSN data struct.
      $dsn = $dp->parse($dsn, $dp->parse_options($o));
      $db  = $dsn->{D};
      $tbl = $dsn->{t};
   }

   my $alter_fk_method = $o->get('alter-foreign-keys-method') || '';
   if ( $alter_fk_method eq 'drop_swap' ) {
      $o->set('swap-tables',    0);
      $o->set('drop-old-table', 0);
   }

   # Explicit --chunk-size disable auto chunk sizing.
   $o->set('chunk-time', 0) if $o->got('chunk-size');
   if (!$o->get('swap-tables') && !$o->get('drop-triggers')) {
       PTDEBUG && _d('Enabling no-drop-new-table since no-swap-tables & no-drop-triggers were specified');
       $o->set('drop-new-table', 0);
   }

   foreach my $opt ( qw(max-load critical-load) ) {
      next unless $o->has($opt);
      my $spec = $o->get($opt);
      eval {
         MySQLStatusWaiter::_parse_spec($o->get($opt));
      };
      if ( $EVAL_ERROR ) {
         chomp $EVAL_ERROR;
         $o->save_error("Invalid --$opt: $EVAL_ERROR");
      }
   }

   # https://bugs.launchpad.net/percona-toolkit/+bug/1010232
   my $n_chunk_index_cols = $o->get('chunk-index-columns');
   if ( defined $n_chunk_index_cols
        && (!$n_chunk_index_cols
            || $n_chunk_index_cols =~ m/\D/
            || $n_chunk_index_cols < 1) ) {
      $o->save_error('Invalid number of --chunk-index columns: '
         . $n_chunk_index_cols);
   }

   my $tries = eval {
      validate_tries($o);
   };
   if ( $EVAL_ERROR ) {
      $o->save_error($EVAL_ERROR);
   }

   if ( !$o->get('drop-triggers') ) {
      $o->set('drop-old-table', 0);
   }

   if ( !$o->get('drop-triggers') && $o->get('preserve-triggers') ) {
      my $msg = "Cannot use --no-drop-triggers along with --preserve-triggers "
              . "since --preserve-triggers implies that the old triggers should be deleted"
              . " and recreated in the new table.\nPlease read the documentation for "
              . "--preserve-triggers";
      _die($msg, INVALID_PARAMETERS);
   }

   if ( $o->get('preserve-triggers') ) {
      $o->set('drop-triggers', 1);
   }

   if ( $o->get('reverse-triggers') ) {
       if ($o->get('drop-old-table')) {
           my $msg = '--reverse-triggers needs --no-drop-old-table';
           _die($msg, INVALID_PARAMETERS);
       }
       if (!$o->get('swap-tables')) {
           my $msg = 'Cannot use --reverse-triggers with --no-swap-tables';
           _die($msg, INVALID_PARAMETERS);
       }
       if ($o->get('preserve-triggers')) {
           my $msg = 'Cannot use --reverse-triggers with --preserve-triggers';
           _die($msg, INVALID_PARAMETERS);
       }
   }

   if ( !$o->get('help') ) {
      if ( @ARGV ) {
         $o->save_error('Specify only one DSN on the command line');
      }

      if ( !$db || !$tbl ) {
         $o->save_error("The DSN must specify a database (D) and a table (t)");
      }

      if ( $o->get('progress') ) {
         eval { Progress->validate_spec($o->get('progress')) };
         if ( $EVAL_ERROR ) {
            chomp $EVAL_ERROR;
            $o->save_error("--progress $EVAL_ERROR");
         }
      }

      # See the "pod-based-option-value-validation" spec for how this may
      # be automagically validated.
      if ( $alter_fk_method
           && $alter_fk_method ne 'auto'
           && $alter_fk_method ne 'rebuild_constraints'
           && $alter_fk_method ne 'drop_swap'
           && $alter_fk_method ne 'none' )
      {
         $o->save_error("Invalid --alter-foreign-keys-method value: $alter_fk_method");
      }

      # Issue a strong warning if alter-foreign-keys-method = none
      if ( $alter_fk_method eq 'none' && !$o->get('force') ) {
         print STDERR "WARNING! Using alter-foreign-keys-method = \"none\". This will typically cause foreign key violations!\nThis method of handling foreign key constraints is only provided so that the database administrator can disable the tool’s built-in functionality if desired.\n\nContinue anyway? (y/N)";
         my $response;
         chomp($response = <STDIN>);
         if ($response !~ /y|(yes)/i) {
            exit 1;
         }
      }

      if ( $alter_fk_method eq 'drop_swap' && !$o->get('drop-new-table') ) {
         $o->save_error("--alter-foreign-keys-method=drop_swap does not work with --no-drop-new-table.");
      }
   }

   eval {
      MasterSlave::check_recursion_method($o->get('recursion-method'));
   };
   if ( $EVAL_ERROR ) {
      $o->save_error("Invalid --recursion-method: $EVAL_ERROR")
   }

   $o->usage_or_errors();

   if ( $o->get('quiet') ) {
      # BARON: this will fail on Windows, where there is no /dev/null. I feel
      # it's a hack, like ignoring a problem instead of fixing it somehow. We
      # should take a look at the things that get printed in a "normal"
      # non-quiet run, and "if !quiet" them, and then do some kind of Logger.pm
      # or Messager.pm module for a future release.
      close STDOUT;
      open  STDOUT, '>', '/dev/null'
         or warn "Cannot reopen STDOUT to /dev/null: $OS_ERROR";
   }

   # ########################################################################
   # Connect to MySQL.
   # ########################################################################
   my $set_on_connect = sub {
      my ($dbh) = @_;
      if (!$o->get('check-foreign-keys')) {
            my $sql = "SET foreign_key_checks=0";
            PTDEBUG && _d($sql);
            print $sql, "\n" if $o->get('print');
            $dbh->do($sql);
      }
      return;
   };

   # Do not call "new Cxn(" directly; use this sub so that set_on_connect
   # is applied to every cxn.
   # BARON: why not make this a subroutine instead of a subroutine variable? I
   # think that can be less confusing. Also, the $set_on_connect variable can be
   # inlined into this subroutine. Many of our tools have a get_dbh() subroutine
   # and it might be good to just make a convention of it.
   my $make_cxn = sub {
      my (%args) = @_;
      my $cxn = Cxn->new(
         %args,
         DSNParser    => $dp,
         OptionParser => $o,
         set          => $set_on_connect,
      );
      eval { $cxn->connect() };  # connect or die trying
      if ( $EVAL_ERROR ) {
         _die("Cannot connect to MySQL: $EVAL_ERROR", MYSQL_CONNECTION_ERROR);
      }
      return $cxn;
   };

   my $cxn     = $make_cxn->(dsn => $dsn);
   my $aux_cxn = $make_cxn->(dsn => $dsn, prev_dsn => $dsn);

   my $cluster = Percona::XtraDB::Cluster->new;
   if ( $cluster->is_cluster_node($cxn) ) {
      # Because of https://bugs.launchpad.net/codership-mysql/+bug/1040108
      # ptc and pt-osc check Threads_running by default for --max-load.
      # Strictly speaking, they can run on 5.5.27 as long as that bug doesn't
      # manifest itself.  If it does, however, then the tools will wait forever.
      $pxc_version = VersionParser->new($cxn->dbh);
      if ( $pxc_version < '5.5.28' ) {
         _die("Percona XtraDB Cluster 5.5.28 or newer is required to run "
            . "this tool on a cluster, but node " . $cxn->name
            . " is running version " . $pxc_version->version
            . ".  Please upgrade the node, or run the tool on a newer node, "
            . "or contact Percona for support.", UNSUPORTED_MYSQL_VERSION);
      }
      if ( $pxc_version < '5.6' && $o->got('max-flow-ctl') ) {
        _die("Option '--max-flow-ctl is only available for PXC version 5.6 "
            . "or higher.", INVALID_PARAMETERS);
      }

      # If wsrep_OSU_method=RSU the "DDL will be only processed locally at
      # the node."  So _table_new (the altered version of table) will not
      # replicate to other nodes but our INSERT..SELECT operations on it
      # will, thereby crashing all other nodes.
      my (undef, $wsrep_osu_method) = $cxn->dbh->selectrow_array(
         "SHOW VARIABLES LIKE 'wsrep\_OSU\_method'");
      if ( lc($wsrep_osu_method || '') ne 'toi' ) {
        _die("wsrep_OSU_method=TOI is required because "
            . $cxn->name . " is a cluster node.  wsrep_OSU_method is "
            . "currently set to " . ($wsrep_osu_method || '') . ".  "
            . "Set it to TOI, or contact Percona for support.", NO_MINIMUM_REQUIREMENTS);
      }
   } elsif ( $o->got('max-flow-ctl') ) {
      _die("Option '--max-flow-ctl' is meant to be used on PXC clusters. "
         ."For normal async replication use '--max-lag' and '--check-interval' "
         ."instead.", INVALID_PARAMETERS);
   }

   # ########################################################################
   # Check if MySQL is new enough to have the triggers we need.
   # Although triggers were introduced in 5.0.2, "Prior to MySQL 5.0.10,
   # triggers cannot contain direct references to tables by name."
   # ########################################################################
   my $server_version = VersionParser->new($cxn->dbh());
   if ( $server_version < '5.0.10' ) {
      _die("This tool requires MySQL 5.0.10 or newer.", UNSUPORTED_MYSQL_VERSION);
   }

   # Use LOCK IN SHARE mode unless MySQL 5.0 because there's a bug like
   # http://bugs.mysql.com/bug.php?id=45694
   my $lock_in_share_mode = $server_version < '5.1' ? 0 : 1;

   # ########################################################################
   # Check if analyze-before-swap is necessary.
   # https://bugs.launchpad.net/percona-toolkit/+bug/1491261
   # ########################################################################
   my $analyze_table = $o->get('analyze-before-swap');
   if ( $o->got('analyze-before-swap') ) {
      # User specified so respect their wish. If --analyze-before-swap, do it
      # regardless of MySQL version and innodb_stats_peristent.
      # If --no-analyze-before-swap, don't do it.
      PTDEBUG && _d('User specified explicit --analyze-before-swap:',
         ($analyze_table ? 'on' : 'off'));
   }
   elsif ( $analyze_table ) {
      # User did not specify --analyze-before-swap on command line, and it
      # defaults to "yes", so auto-check for the conditions it's affected by
      # and enable only if those conditions are true.
      if ( $server_version >= '5.6' ) {
         my (undef, $innodb_stats_persistent) = $cxn->dbh->selectrow_array(
            "SHOW VARIABLES LIKE 'innodb_stats_persistent'");
         if ($innodb_stats_persistent eq 'ON' || $innodb_stats_persistent eq '1') {
            PTDEBUG && _d('innodb_stats_peristent is ON, enabling --analyze-before-swap');
            $analyze_table = 1;
         } else {
            PTDEBUG && _d('innodb_stats_peristent is OFF, disabling --analyze-before-swap');
            $analyze_table = 0;
         }
      } else {
         PTDEBUG && _d('MySQL < 5.6, disabling --analyze-before-swap');
         $analyze_table = 0;
      }
   }

   # ########################################################################
   # Create --plugin.
   # ########################################################################
   my $plugin;
   if ( my $file = $o->get('plugin') ) {
      _die("--plugin file $file does not exist", INVALID_PLUGIN_FILE) unless -f $file;
      eval {
         require $file;
      };
      _die("Error loading --plugin $file: $EVAL_ERROR", INVALID_PLUGIN_FILE) if $EVAL_ERROR;
      eval {
         $plugin = pt_online_schema_change_plugin->new(
            cxn     => $cxn,
            aux_cxn => $aux_cxn,
            alter   => $o->get('alter'),
            execute => $o->get('execute'),
            dry_run => $o->get('dry-run'),
            print   => $o->get('print'),
            quiet   => $o->get('quiet'),
            Quoter  => $q,
         );
      };
      _die("Error creating --plugin: $EVAL_ERROR", INVALID_PLUGIN_FILE) if $EVAL_ERROR;
      print "Created plugin from $file.\n";
   }

   # ########################################################################
   # Setup lag and load monitors.
   # ########################################################################
   my $slaves;         # all slaves that are found or specified
   my $slave_lag_cxns; # slaves whose lag we'll check
   my $replica_lag;    # ReplicaLagWaiter object
   my $replica_lag_pr; # Progress for ReplicaLagWaiter
   my $flow_ctl;       # FlowControlWaiter object
   my $flow_ctl_pr;    # Progress for FlowControlWaiter
   my $sys_load;       # MySQLStatusWaiter object
   my $sys_load_pr;    # Progress for MySQLStatusWaiter object
   my $process_error;  # Used if drop_swap fails

   if ( $o->get('execute') ) {
      # #####################################################################
      # Find and connect to slaves.
      # #####################################################################
      my $ms = new MasterSlave(
         OptionParser => $o,
         DSNParser    => $dp,
         Quoter       => $q,
         channel      => $o->get('channel'),
      );

     my $slaves_to_skip = $o->get('skip-check-slave-lag');

     my $get_slaves_cb = sub {
         my ($intolerant) = @_;
         my $slaves =$ms->get_slaves(
               dbh      => $cxn->dbh(),
               dsn      => $cxn->dsn(),
               make_cxn => sub {
                  return $make_cxn->(
                     @_,
                     prev_dsn => $cxn->dsn(),
                     errok => (not $intolerant)
                  );
               },
            );

         if ($slaves_to_skip) {
            my $filtered_slaves = [];
            for my $slave (@$slaves) {
               for my $slave_to_skip (@$slaves_to_skip) {
                  if ($slave->{dsn}->{h} eq $slave_to_skip->{h} && $slave->{dsn}->{P} eq $slave_to_skip->{P}) {
                     print "Skipping slave " . $slave->description() . "\n";
                  } else {
                     push @$filtered_slaves, $slave;
                  }
               }
            }
            $slaves = $filtered_slaves;
         }

         return $slaves;
      };

      ### first ever call only: do not tolerate connection errors
      $slaves = $get_slaves_cb->('intolerant');

      PTDEBUG && _d(scalar @$slaves, 'slaves found');
      if ( scalar @$slaves ) {
         print "Found " . scalar(@$slaves) . " slaves:\n";
         foreach my $cxn ( @$slaves ) {
            print $cxn->description()."\n";
         }
      }
      elsif ( ($o->get('recursion-method') || '') ne 'none') {
         print "No slaves found.  See --recursion-method if host "
               . $cxn->name() . " has slaves.\n";
      }
      else {
         print "Ignoring all slaves because --recursion-method=none "
            . "was specified\n";
      }

      if ( my $dsn = $o->get('check-slave-lag') ) {
         PTDEBUG && _d('Will use --check-slave-lag to check for slave lag');
         my $cxn = $make_cxn->(
            dsn_string => $o->get('check-slave-lag'),
            #prev_dsn   => $cxn->dsn(),
         );
         $slave_lag_cxns = [ $cxn ];
         $get_slaves_cb  = undef;
      }
      else {
         PTDEBUG && _d('Will check slave lag on all slaves');
         $slave_lag_cxns = $slaves;
      }

      if ( $slave_lag_cxns && scalar @$slave_lag_cxns ) {
         print "Will check slave lag on:\n";
         foreach my $cxn ( @$slave_lag_cxns ) {
            print $cxn->description()."\n";
         }
      }
      else {
         print "Not checking slave lag because no slaves were found "
               . "and --check-slave-lag was not specified.\n";
      }
      # Before starting, check the replication is not using replications channels or that --channel was specified
      for my $slave (@$slave_lag_cxns) {
          eval {
             my $ss = $ms->get_slave_status($slave->{dbh});
          };
          if ($EVAL_ERROR) {
              die $EVAL_ERROR;
          }
      }

      # #####################################################################
      # Check for replication filters.
      # #####################################################################
      if ( $o->get('check-replication-filters') ) {
         PTDEBUG && _d("Checking slave replication filters");
         my @all_repl_filters;
         foreach my $slave ( @$slaves ) {
            my $repl_filters = $ms->get_replication_filters(
               dbh => $slave->dbh(),
            );
            if ( keys %$repl_filters ) {
               push @all_repl_filters,
                  { name    => $slave->name(),
                    filters => $repl_filters,
                  };
            }
         }
         if ( @all_repl_filters ) {
            my $msg = "Replication filters are set on these hosts:\n";
            foreach my $host ( @all_repl_filters ) {
               my $filters = $host->{filters};
               $msg .= "  $host->{name}\n"
                     . join("\n", map { "    $_ = $host->{filters}->{$_}" }
                            keys %{$host->{filters}})
                     . "\n";
            }
            $msg .= "Please read the --check-replication-filters documentation "
                  . "to learn how to solve this problem.";
            _die($msg, INVALID_PARAMETERS);
         }
      }

      # #####################################################################
      # Make a ReplicaLagWaiter to help wait for slaves after each chunk.
      # Note: the "sleep" function is also used by MySQLStatusWaiter and
      #       FlowControlWaiter
      # #####################################################################
      my $sleep = sub {
         # Don't let the master dbh die while waiting for slaves because we
         # may wait a very long time for slaves.
         my $dbh = $cxn->dbh();
         if ( !$dbh || !$dbh->ping() ) {
            eval { $dbh = $cxn->connect() };  # connect or die trying
            if ( $EVAL_ERROR ) {
               $oktorun = 0;  # flag for cleanup tasks
               chomp $EVAL_ERROR;
               _die("Lost connection to " . $cxn->name() . " while waiting for "
                  . "replica lag ($EVAL_ERROR)", LOST_MYSQL_CONNECTION);
            }
         }
         $dbh->do("SELECT 'pt-online-schema-change keepalive'");
         sleep $o->get('check-interval');
         return;
      };

      my $get_lag;
      # The plugin is able to override the slavelag check so tools like
      # pt-heartbeat or other replicators (Tungsten...) can be used to
      # measure replication lag
      if ( $plugin && $plugin->can('get_slave_lag') ) {
         $get_lag = $plugin->get_slave_lag(oktorun => \$oktorun);
      }
      else {
         $get_lag = sub {
            my ($cxn) = @_;
            my $dbh = $cxn->dbh();
            if ( !$dbh || !$dbh->ping() ) {
               eval { $dbh = $cxn->connect() };  # connect or die trying
               if ( $EVAL_ERROR ) {
                  # As the docs say: "The tool waits forever for replicas
                  # to stop lagging.  If any replica is stopped, the tool
                  # waits forever until the replica is started."
                  # https://bugs.launchpad.net/percona-toolkit/+bug/1402051
                  #TODO REMOVE DEBUG
                  PTDEBUG && _d('2> Cannot connect to', $cxn->name(), ':',
                     $EVAL_ERROR);
                  die '2> Cannot connect to '. $cxn->name() . ':' . $EVAL_ERROR;
                  # Make ReplicaLagWaiter::wait() report slave is stopped.
                  return undef;
               }
            }
            my $lag;
            eval {
               $lag = $ms->get_slave_lag($dbh);
            };
            if ( $EVAL_ERROR ) {
               PTDEBUG && _d('Cannot get lag for', $cxn->name(), ':', $EVAL_ERROR);
                  die '2> Cannot connect to '. $cxn->name() . ':' . $EVAL_ERROR;
            }
            return $lag; # undef if error
         };
      }

      $replica_lag = new ReplicaLagWaiter(
         slaves        => $slave_lag_cxns,
         get_slaves_cb => $get_slaves_cb,
         max_lag       => $o->get('max-lag'),
         oktorun       => sub { return $oktorun },
         get_lag       => $get_lag,
         sleep         => $sleep,
      );

      my $get_status;
      {
         my $sql = "SHOW GLOBAL STATUS LIKE ?";
         my $sth = $cxn->dbh()->prepare($sql);

         $get_status = sub {
            my ($var) = @_;
            PTDEBUG && _d($sth->{Statement}, $var);
            $sth->execute($var);
            my (undef, $val) = $sth->fetchrow_array();
            return $val;
         };
      }

      eval {
         $sys_load = new MySQLStatusWaiter(
            max_spec      => $o->get('max-load'),
            critical_spec => $o->get('critical-load'),
            get_status    => $get_status,
            oktorun       => sub { return $oktorun },
            sleep         => $sleep,
         );
      };
      if ( $EVAL_ERROR ) {
         chomp $EVAL_ERROR;
         _die("Error checking --max-load or --critial-load: $EVAL_ERROR.  "
            . "Check that the variables specified for --max-load and "
            . "--critical-load are spelled correctly and exist in "
            . "SHOW GLOBAL STATUS.  Current values for these options are:\n"
            . "  --max-load " . (join(',', @{$o->get('max-load')})) . "\n"
            . "  --critial-load "  . (join(',', @{$o->get('critical-load')}))
            , INVALID_PARAMETERS);
      }

      if ( $pxc_version >= '5.6' && $o->got('max-flow-ctl') ) {
            $flow_ctl = new FlowControlWaiter(
               node          => $cxn->dbh(),
               max_flow_ctl  => $o->get('max-flow-ctl'),
               oktorun       => sub { return $oktorun },
               sleep         => $sleep,
            );
      }

      if ( $o->get('progress') ) {
         $replica_lag_pr = new Progress(
            jobsize => scalar @$slaves,
            spec    => $o->get('progress'),
            name    => "Waiting for replicas to catch up",  # not used
         );

         $sys_load_pr = new Progress(
            jobsize => scalar @{$o->get('max-load')},
            spec    => $o->get('progress'),
            name    => "Waiting for --max-load", # not used
         );

         if ( $pxc_version >= '5.6' && $o->got('max-flow-ctl') ) {
            $flow_ctl_pr = new Progress(
               jobsize => $o->get('max-flow-ctl'),
               spec    => $o->get('progress'),
               name    => "Waiting for flow control to abate", # not used
            );
         }
      }
   }

   # ########################################################################
   # Do the version-check
   # ########################################################################
   if ( $o->get('version-check') && (!$o->has('quiet') || !$o->get('quiet')) ) {
      VersionCheck::version_check(
         force     => $o->got('version-check'),
         instances => [
            map (
               { +{ dbh => $_->dbh(), dsn => $_->dsn() } }
               $cxn, ($slaves ? @$slaves : ())
            )
         ],
      );
   }

   # ########################################################################
   # Setup and check the original table.
   # ########################################################################
   my $tp = TableParser->new(Quoter => $q);

   # Common table data struct (that modules like NibbleIterator expect).
   my $orig_tbl = {
      db   => $db,
      tbl  => $tbl,
      name => $q->quote($db, $tbl),
   };

   check_orig_table(
      orig_tbl     => $orig_tbl,
      Cxn          => $cxn,
      OptionParser => $o,
      TableParser  => $tp,
      Quoter       => $q,
   );

   # ########################################################################
   # Print --tries.
   # ########################################################################
   print "Operation, tries, wait:\n";
   {
      my $fmt = "  %s, %s, %s\n";
      foreach my $op ( sort keys %$tries ) {
         printf $fmt, $op, $tries->{$op}->{tries}, $tries->{$op}->{wait};
      }
   }

   # ########################################################################
   # Get child tables of the original table, if necessary.
   # ########################################################################
   my $child_tables;

   my $have_child_tables = find_child_tables(
         tbl    => $orig_tbl,
         Cxn    => $cxn,
         Quoter => $q,
         only_same_schema_fks => $o->get('only-same-schema-fks'),
      );

   my $vp = VersionParser->new($cxn->dbh());
   if (($vp->cmp('8.0.14') >= 0 && $vp->cmp('8.0.17') <= 0) && $vp->flavor() !~ m/maria/i) {
       my $msg = "There is an error in MySQL that makes the server to die when trying to ".
                 "rename a table with FKs. See https://bugs.mysql.com/bug.php?id=96145\n".
                 "Since pt-online-schema change needs to rename the old <-> new tables as the final " .
                 "step, and the requested table has FKs, it cannot be executed under the current MySQL version";
       _die($msg, NO_MINIMUM_REQUIREMENTS);
   }

   if ( ($alter_fk_method || '') eq 'none' ) {
      print "Not updating foreign keys because "
         . "--alter-foreign-keys-method=none.  Foreign keys "
         . "that reference the table will no longer work.\n";
   }
   else {
      $child_tables = find_child_tables(
         tbl    => $orig_tbl,
         Cxn    => $cxn,
         Quoter => $q,
         only_same_schema_fks => $o->get('only-same-schema-fks'),
      );
      if ( !$child_tables ) {
         if ( $alter_fk_method ) {
            warn "No foreign keys reference $orig_tbl->{name}; ignoring "
               . "--alter-foreign-keys-method.\n";

            if ( $alter_fk_method eq 'drop_swap' ) {
               # These opts are disabled at the start if the user specifies
               # the drop_swap method, but now that we know there are no
               # child tables, we must re-enable these to make the alter work.
               $o->set('swap-tables',    1);
               $o->set('drop-old-table', 1);
            }

            $alter_fk_method = '';
         }
         # No child tables and --alter-fk-method wasn't specified,
         # so nothing to do.
      }
      else {
         print "Child tables:\n";
         foreach my $child_table ( @$child_tables ) {
            printf "  %s (approx. %s rows)\n",
               $child_table->{name},
               $child_table->{row_est} || '?';
         }

         # TODO: Fix self referencing foreign keys handling.
         # See: https://jira.percona.com/browse/PT-1802
         #      https://jira.percona.com/browse/PT-1853
         if (_has_self_ref_fks($orig_tbl->{db}, $orig_tbl->{tbl}, $child_tables) && $o->get('check-foreign-keys')) {
             print "The table has self-referencing foreign keys and that might lead to errors.\n";
             print "Use --no-check-foreign-keys to disable this check.\n";
             return 1;
         }

         if ( $alter_fk_method ) {
            # Let the user know how we're going to update the child table
            # fk refs.
            my $choice
            = $alter_fk_method eq 'none' ? "not"
            : $alter_fk_method eq 'auto' ? "automatically choose the method to"
            :                              "use the $alter_fk_method method to";
            print "Will $choice update foreign keys.\n";
         }
         else {
            print "You did not specify --alter-foreign-keys-method, but there "
                . "are foreign keys that reference the table. "
                . "Please read the tool's documentation carefully.\n";
            return 1;
         }
      }
   }

   # ########################################################################
   # XXX
   # Ready to begin the alter!  Nothing has been changed on the server at
   # this point; we've just checked and looked for things.  Past this point,
   # the code is live if --execute, else it's doing a --dry-run.  Or, if
   # the user didn't read the docs, we may bail out here.
   # XXX
   # ########################################################################
   if ( $o->get('dry-run') ) {
      print "Starting a dry run.  $orig_tbl->{name} will not be altered.  "
          . "Specify --execute instead of --dry-run to alter the table.\n";
   }
   elsif ( $o->get('execute') ) {
      print "Altering $orig_tbl->{name}...\n";
   }
   else {
      print "Exiting without altering $orig_tbl->{name} because neither "
        . "--dry-run nor --execute was specified.  Please read the tool's "
        . "documentation carefully before using this tool.\n";
      return 1;
   }

   # ########################################################################
   # Create a cleanup task object to undo changes (i.e. clean up) if the
   # code dies, or we may call this explicitly at the end if all goes well.
   # ########################################################################
   my @cleanup_tasks;
   my $cleanup = new CleanupTask(
      sub {
         # XXX We shouldn't copy $EVAL_ERROR here, but I found that
         # errors are not re-thrown in tests.  If you comment (*) out this
         # line and the die below, an error fails:
         # not ok 5 - Doesn't try forever to find a new table name
         #   Failed test 'Doesn't try forever to find a new table name'
         #   at /Users/daniel/p/pt-osc-2.1.1/lib/PerconaTest.pm line 559.
         #                   ''
         #   doesn't match '(?-xism:Failed to find a unique new table name)'

         # (*) Frank:  commented them out because it caused infinite loop
         # and the mentioned test error doesn't arise

         my $original_error = $EVAL_ERROR;

         foreach my $task ( reverse @cleanup_tasks ) {
            eval {
               $task->();
            };
            if ( $EVAL_ERROR ) {
               warn "Error cleaning up: $EVAL_ERROR\n";
            }
         }
         die $original_error if $original_error;  # rethrow original error
         return;
      }
   );

   local $SIG{__DIE__} = sub {
      return if $EXCEPTIONS_BEING_CAUGHT;
      local $EVAL_ERROR = $_[0];
      undef $cleanup;
      die @_;
   };

   # The last cleanup task is to report whether or not the orig table
   # was altered.
   push @cleanup_tasks, sub {
      PTDEBUG && _d('Clean up done, report if orig table was altered');
      if ( $o->get('dry-run') ) {
         print "Dry run complete.  $orig_tbl->{name} was not altered.\n";
      }
      else {
         if ( $orig_tbl->{swapped} ) {
            if ( $orig_tbl->{success} ) {
               print "Successfully altered $orig_tbl->{name}.\n";
            }
            else {
               print "Altered $orig_tbl->{name} but there were errors "
                  . "or warnings.\n";
            }
         }
         else {
            print "$orig_tbl->{name} was not altered.\n";
         }
      }
      return;
   };

   # The 2nd to last cleanup task is printing the --statistics which
   # may reveal something about the failure.
   if ( $o->get('statistics') ) {
      push @cleanup_tasks, sub {
         my $n = max( map { length $_ } keys %stats );
         my $fmt = "# %-${n}s %5s\n";
         printf $fmt, 'Event', 'Count';
         printf $fmt, ('=' x $n),'=====';
         foreach my $event ( sort keys %stats ) {
            printf $fmt,
               $event, (defined $stats{$event} ? $stats{$event} : '?');
         }
      };
   }

   # ########################################################################
   # Check the --alter statement.
   # ########################################################################
   my $renamed_cols = {};
   if ( my $alter = $o->get('alter') ) {
      $renamed_cols = find_renamed_cols(
         alter       => $o->get('alter'),
         TableParser => $tp,
      );

      if ( $o->get('check-alter') ) {
         check_alter(
            tbl          => $orig_tbl,
            alter        => $alter,
            dry_run      => $o->get('dry-run'),
            renamed_cols => $renamed_cols,
            Cxn          => $cxn,
            TableParser  => $tp,
            OptionParser => $o,
         );
      }
   }

   if ( %$renamed_cols && !$o->get('dry-run') ) {
      print "Renaming columns:\n"
         . join("\n", map { "  $_ to $renamed_cols->{$_}" }
            sort keys %$renamed_cols)
         . "\n";
   }

   # ########################################################################
   # Check and create PID file if user specified --pid.
   # ########################################################################
   my $daemon = Daemon->new(
      daemonize => 0,  # not daemoninzing, just PID file
      pid_file  => $o->get('pid'),
   );
   $daemon->run();

   # ########################################################################
   # Init the --plugin.
   # ########################################################################

   # --plugin hook
   if ( $plugin && $plugin->can('init') ) {
      $plugin->init(
         orig_tbl       => $orig_tbl,
         child_tables   => $child_tables,
         renamed_cols   => $renamed_cols,
         slaves         => $slaves,
         slave_lag_cxns => $slave_lag_cxns,
      );
   }

   # #####################################################################
   # Step 1: Create the new table.
   # #####################################################################

   my $new_table_name   = $o->get('new-table-name');
   my $new_table_prefix = $o->got('new-table-name') ? undef : '_';

   # --plugin hook
  if ( $plugin && $plugin->can('before_create_new_table') ) {
      $plugin->before_create_new_table(
            new_table_name   => $new_table_name,
            new_table_prefix => $new_table_prefix,
      );
   }

   my $new_tbl;
   eval {
      $new_tbl = create_new_table(
         new_table_name   => $new_table_name,
         new_table_prefix => $new_table_prefix,
         orig_tbl         => $orig_tbl,
         Cxn              => $cxn,
         Quoter           => $q,
         OptionParser     => $o,
         TableParser      => $tp,
      );
   };
   if ( $EVAL_ERROR ) {
      _die("Error creating new table: $EVAL_ERROR", ERROR_CREATING_NEW_TABLE);
   }

   # If the new table still exists, drop it unless the tool was interrupted.
   push @cleanup_tasks, sub {
      PTDEBUG && _d('Clean up new table');
      my $new_tbl_exists = $tp->check_table(
         dbh => $cxn->dbh(),
         db  => $new_tbl->{db},
         tbl => $new_tbl->{tbl},
      );
      PTDEBUG && _d('New table exists:', $new_tbl_exists ? 'yes' : 'no');
      return unless $new_tbl_exists;

      my $sql = "DROP TABLE IF EXISTS $new_tbl->{name};";
      if ( !$oktorun ) {
         # The tool was interrupted, so do not drop the new table
         # in case the user wants to resume (once resume capability
         # is implemented).
         print "Not dropping the new table $new_tbl->{name} because "
             . "the tool was interrupted.  To drop the new table, "
             . "execute:\n$sql\n";
      }
      elsif ( $orig_tbl->{copied} && !$orig_tbl->{swapped} ) {
         print "Not dropping the new table $new_tbl->{name} because "
             . "--swap-tables failed.  To drop the new table, "
             . "execute:\n$sql\n";
      }
      elsif ( !$o->get('drop-new-table') ) {
         # https://bugs.launchpad.net/percona-toolkit/+bug/998831
         print "Not dropping the new table $new_tbl->{name} because "
             . "--no-drop-new-table was specified.  To drop the new table, "
             . "execute:\n$sql\n";
      }
      elsif ( @triggers_not_dropped ) {
         # https://bugs.launchpad.net/percona-toolkit/+bug/1188002
         print "Not dropping the new table $new_tbl->{name} because "
            . "dropping these triggers failed:\n"
            . join("\n", map { "  $_" } @triggers_not_dropped)
            . "\nThese triggers must be dropped before dropping "
            . "$new_tbl->{name}, else writing to $orig_tbl->{name} will "
            . "cause MySQL error 1146 (42S02): \"Table $new_tbl->{name} "
            . " doesn't exist\".\n";
      }
      elsif ($process_error) {
          print "Not dropping new table because FKs processing has failed.\n";
      }
      else {
         print ts("Dropping new table...\n");
         print $sql, "\n" if $o->get('print');
         PTDEBUG && _d($sql);
         eval {
            $cxn->dbh()->do($sql);
         };
         if ( $EVAL_ERROR ) {
            warn ts("Error dropping new table $new_tbl->{name}: $EVAL_ERROR\n"
               . "To try dropping the new table again, execute:\n$sql\n");
         }
         print ts("Dropped new table OK.\n");
      }
   };

   my $table_is_replicated;
   if ( $slaves && scalar @$slaves && $table_is_replicated) {
      foreach my $slave (@$slaves) {
         my ($pr, $pr_first_report);
         if ( $o->get('progress') ) {
            $pr = new Progress(
               jobsize => scalar @$slaves,
               spec    => $o->get('progress'),
               name    => "Waiting for " . $slave->name(),
            );
            $pr_first_report = sub {
               print "Waiting forever for new table $new_tbl->{name} to replicate "
                  . "to " . $slave->name() . "...\n";
            };
         }
         $pr->start() if $pr;
         my $has_table = 0;
         while ( !$has_table ) {
            $has_table = $tp->check_table(
               dbh => $slave->dbh(),
               db  => $new_tbl->{db},
               tbl => $new_tbl->{tbl}
            );
            last if $has_table;
            $pr->update(
               sub { return 0; },
               first_report => $pr_first_report,
            ) if $pr;
            sleep 1;
         }
      }
   }

   # --plugin hook
   if ( $plugin && $plugin->can('after_create_new_table') ) {
      $plugin->after_create_new_table(
         new_tbl => $new_tbl,
      );
   }

   # #####################################################################
   # Step 2: Alter the new, empty table.  This should be very quick,
   # or die if the user specified a bad alter statement.
   # #####################################################################

   # --plugin hook
   if ( $plugin && $plugin->can('before_alter_new_table') ) {
      $plugin->before_alter_new_table(
         new_tbl => $new_tbl,
      );
   }

   if ( my $alter = $o->get('alter') ) {
      print "Altering new table...\n";
      my $sql = "ALTER TABLE $new_tbl->{name} $alter";
      print $sql, "\n" if $o->get('print');
      PTDEBUG && _d($sql);
      eval {
         $cxn->dbh()->do($sql);
      };
      if ( $EVAL_ERROR ) {
         # this is trapped by a signal handler. Don't replace it with _die
         die "Error altering new table $new_tbl->{name}: $EVAL_ERROR\n";
      }
      print "Altered $new_tbl->{name} OK.\n";
   }

   # Get the new table struct.  This shouldn't die because
   # we just created the table successfully so we know it's
   # there.  But the ghost of Ryan is everywhere.
   my $ddl = $tp->get_create_table(
      $cxn->dbh(),
      $new_tbl->{db},
      $new_tbl->{tbl},
   );
   $new_tbl->{tbl_struct} = $tp->parse($ddl);

   # Determine what columns the original and new table share.
   # If the user drops a col, that's easy: just don't copy it.  If they
   # add a column, it must have a default value.  Other alterations
   # may or may not affect the copy process--we'll know when we try!
   # Col posn (position) is just for looks because user's like
   # to see columns listed in their original order, not Perl's
   # random hash key sorting.
   my $col_posn    = $orig_tbl->{tbl_struct}->{col_posn};
   my $orig_cols   = $orig_tbl->{tbl_struct}->{is_col};
   my $new_cols    = $new_tbl->{tbl_struct}->{is_col};
   my @common_cols = map  { +{ old => $_, new => $renamed_cols->{$_} || $_ } }
                     sort { $col_posn->{$a} <=> $col_posn->{$b} }
                     grep { $new_cols->{$_} || $renamed_cols->{$_} }
                     keys %$orig_cols;
   PTDEBUG && _d('Common columns', Dumper(\@common_cols));

   # Find a pk or unique index to use for the delete trigger.  can_nibble()
   # above returns an index, but NibbleIterator will use non-unique indexes,
   # so we have to do this again here.
   {
      my $indexes = $new_tbl->{tbl_struct}->{keys}; # brevity
      foreach my $index ( $tp->sort_indexes($new_tbl->{tbl_struct}) ) {
         if ( $index eq 'PRIMARY' || ($indexes->{$index}->{is_unique} && $indexes->{$index}->{is_nullable} == 0)) {
            PTDEBUG && _d('Delete trigger new index:', Dumper($index));
            $new_tbl->{del_index} = $index;
            last;
         }
      }
   }

   {
      my $indexes = $orig_tbl->{tbl_struct}->{keys}; # brevity
      foreach my $index ( $tp->sort_indexes($orig_tbl->{tbl_struct}) ) {
         if ( $index eq 'PRIMARY' || $indexes->{$index}->{is_unique} ) {
            PTDEBUG && _d('Delete trigger orig index:', Dumper($index));
            $orig_tbl->{del_index} = $index;
            last;
         }
      }
      PTDEBUG && _d('Orig table delete index:', $orig_tbl->{del_index});
   }

   if ( !$new_tbl->{del_index} ) {
      _die("The new table $new_tbl->{name} does not have a PRIMARY KEY "
        . "or a unique index which is required for the DELETE trigger.\n"
        . "Please check you have at least one UNIQUE and NOT NULLABLE index.",
        NO_PRIMARY_OR_UNIQUE_KEY);
   }

   # Determine whether to use the new or orig table delete index.
   # The new table del index is preferred due to
   # https://bugs.launchpad.net/percona-toolkit/+bug/1062324
   # In short, if the chosen del index is re-created with new columns,
   # its original columns may be dropped, so just use its new columns.
   # But, due to https://bugs.launchpad.net/percona-toolkit/+bug/1103672,
   # the chosen del index on the new table may reference columns which
   # do not/no longer exist in the orig table, so we check for this
   # and, if it's the case, we fall back to using the del index from
   # the orig table.
   my $del_tbl = $new_tbl; # preferred
   my $new_del_index_cols  # brevity
      = $new_tbl->{tbl_struct}->{keys}->{ $new_tbl->{del_index} }->{cols};
   foreach my $new_del_index_col ( @$new_del_index_cols ) {
      if ( !exists $orig_cols->{$new_del_index_col} ) {
         if ( !$orig_tbl->{del_index} ) {
            _die("The new table index $new_tbl->{del_index} would be used "
               . "for the DELETE trigger, but it uses column "
               . "$new_del_index_col which does not exist in the original "
               . "table and the original table does not have a PRIMARY KEY "
               . "or a unique index to use for the DELETE trigger.",
               NO_PRIMARY_OR_UNIQUE_KEY);
         }
         print "Using original table index $orig_tbl->{del_index} for the "
            . "DELETE trigger instead of new table index $new_tbl->{del_index} "
            . "because the new table index uses column $new_del_index_col "
            . "which does not exist in the original table.\n";
         $del_tbl = $orig_tbl;
         last;
      }
   }

   {
      my $del_cols
         = $del_tbl->{tbl_struct}->{keys}->{ $del_tbl->{del_index} }->{cols};
      PTDEBUG && _d('Index for delete trigger: table', $del_tbl->{name},
         'index', $del_tbl->{del_index},
         'columns', @$del_cols);
   }

   # --plugin hook
   if ( $plugin && $plugin->can('after_alter_new_table') ) {
      $plugin->after_alter_new_table(
         new_tbl => $new_tbl,
         del_tbl => $del_tbl,
      );
   }

   # ########################################################################
   # Step 3: Create the triggers to capture changes on the original table and
   # apply them to the new table.
   # ########################################################################

   my $retry = new Retry();

   # Drop the triggers.  We can save this cleanup task before
   # adding the triggers because if adding them fails, this will be
   # called which will drop whichever triggers were created.
   my $drop_triggers = $o->get('drop-triggers');
   push @cleanup_tasks, sub {
      PTDEBUG && _d('Clean up triggers');
      # --plugin hook
      if ( $plugin && $plugin->can('before_drop_triggers') ) {
         $plugin->before_drop_triggers(
            oktorun           => $oktorun,
            drop_triggers     => $drop_triggers,
            drop_trigger_sqls => \@drop_trigger_sqls,
         );
      }

      if ( !$oktorun ) {
         print "Not dropping triggers because the tool was interrupted.  "
             . "To drop the triggers, execute:\n"
             . join("\n", @drop_trigger_sqls) . "\n";
      }
      elsif ( !$drop_triggers  ) {
         print "Not dropping triggers because --no-drop-triggers was "
         . "specified.  To drop the triggers, execute:\n"
         . join("\n", @drop_trigger_sqls) . "\n";
      }
      else {
         drop_triggers(
            tbl          => $orig_tbl,
            Cxn          => $cxn,
            Quoter       => $q,
            OptionParser => $o,
            Retry        => $retry,
            tries        => $tries,
            stats        => \%stats,
         );
      }
   };

   # --plugin hook
   if ( $plugin && $plugin->can('before_create_triggers') ) {
      $plugin->before_create_triggers();
   }

   my @trigger_names = eval {
      create_triggers(
         orig_tbl     => $orig_tbl,
         new_tbl      => $new_tbl,
         del_tbl      => $del_tbl,
         columns      => \@common_cols,
         Cxn          => $cxn,
         Quoter       => $q,
         OptionParser => $o,
         Retry        => $retry,
         tries        => $tries,
         stats        => \%stats,
      );
   };
   if ( $EVAL_ERROR ) {
      _die("Error creating triggers: $EVAL_ERROR", ERROR_CREATING_TRIGGERS);
   };

   if ( $o->get('reverse-triggers') ) {
       print "Adding reverse triggers\n";
       eval {
           my $old_tbl_name = '_'.$orig_tbl->{tbl}.'_old';
           my $new_tbl_name = '_'.$orig_tbl->{tbl}.'_new';

           my $old_tbl = {
               db   => $orig_tbl->{db},
               name => '`'.$orig_tbl->{db}.'`.`'.$old_tbl_name.'`',
               tbl  => $old_tbl_name,
           };
           my $new_tbl = {
               db   => $orig_tbl->{db},
               name => '`'.$orig_tbl->{db}.'`.`'.$new_tbl_name.'`',
               tbl  => $new_tbl_name,
           };
           my $triggers=create_triggers(
               orig_tbl         => $new_tbl,
               new_tbl          => $old_tbl,
               del_tbl          => $orig_tbl,
               columns          => \@common_cols,
               Cxn              => $cxn,
               Quoter           => $q,
               OptionParser     => $o,
               Retry            => $retry,
               tries            => $tries,
               stats            => \%stats,
               reverse_triggers => 1,
           );
       };
       if ( $EVAL_ERROR ) {
          _die("Error creating reverse triggers: $EVAL_ERROR", ERROR_CREATING_REVERSE_TRIGGERS);
       };
   }

   # --plugin hook
   if ( $plugin && $plugin->can('after_create_triggers') ) {
      $plugin->after_create_triggers();
   }

   # #####################################################################
   # Step 4: Copy rows.
   # #####################################################################

   # The hashref of callbacks below is what NibbleIterator calls internally
   # to do all the copy work.  The callbacks do not need to eval their work
   # because the higher call to $nibble_iter->next() is eval'ed which will
   # catch any errors in the callbacks.
   my $total_rows = 0;
   my $total_time = 0;
   my $avg_rate   = 0;  # rows/second
   my $limit      = $o->get('chunk-size-limit');  # brevity
   my $chunk_time = $o->get('chunk-time');        # brevity

   my $callbacks = {
      init => sub {
         my (%args) = @_;
         my $tbl         = $args{tbl};
         my $nibble_iter = $args{NibbleIterator};
         my $statements  = $nibble_iter->statements();
         my $boundary    = $nibble_iter->boundaries();

         if ( $o->get('dry-run') ) {
            print "Not copying rows because this is a dry run.\n";
         }
         else {
            if ( !$nibble_iter->one_nibble() && !$boundary->{first_lower} ) {
               # https://bugs.launchpad.net/percona-toolkit/+bug/1020997
               print "$tbl->{name} is empty, no rows to copy.\n";
               return;
            }
            else {
               print ts("Copying approximately "
                  . $nibble_iter->row_estimate() . " rows...\n");
            }
         }

         if ( $o->get('print') ) {
            # Print the checksum and next boundary statements.
            foreach my $sth ( sort keys %$statements ) {
               next if $sth =~ m/^explain/;
               if ( $statements->{$sth} ) {
                  print $statements->{$sth}->{Statement}, "\n";
               }
            }
         }

         return unless $o->get('execute');

         # If table is a single chunk on the master, make sure it's also
         # a single chunk on all slaves.  E.g. if a slave is out of sync
         # and has a lot more rows than the master, single chunking on the
         # master could cause the slave to choke.
         my $failed_to_nibble;
         if ( $nibble_iter->one_nibble() ) {
            PTDEBUG && _d('Getting table row estimate on replicas');
            my @too_large;
            foreach my $slave ( @$slaves ) {
               my ($n_rows) = NibbleIterator::get_row_estimate(
                  Cxn   => $slave,
                  tbl   => $tbl,
               );
               PTDEBUG && _d('Table on',$slave->name(),'has', $n_rows, 'rows');
               if ( $limit && $n_rows && $n_rows > ($tbl->{chunk_size} * $limit) ) {
                  PTDEBUG && _d('Table too large on', $slave->name());
                  push @too_large, [$slave->name(), $n_rows || 0];
               }
            }
            if ( @too_large ) {
               my $msg
                  = "Cannot copy table $tbl->{name} because"
                  . " on the master it would be checksummed in one chunk"
                  . " but on these replicas it has too many rows:\n";
               foreach my $info ( @too_large ) {
                  $msg .= "  $info->[1] rows on $info->[0]\n";
               }
               $msg .= "The current chunk size limit is "
                     . ($tbl->{chunk_size} * $limit)
                     . " rows (chunk size=$tbl->{chunk_size}"
                     . " * chunk size limit=$limit).\n";
               warn $msg;
               $failed_to_nibble = 1;
               warn "Switching to nibble\n";
               $nibble_iter->switch_to_nibble();
               # die ts($msg);
            } else {
               return 1;
            }
         }
         if (!$nibble_iter->one_nibble()) { # chunking the table
            if ( $o->get('check-plan') ) {
               my $idx_len = new IndexLength(Quoter => $q);
               my ($key_len, $key) = $idx_len->index_length(
                  Cxn          => $args{Cxn},
                  tbl          => $tbl,
                  index        => $nibble_iter->nibble_index(),
                  n_index_cols => $o->get('chunk-index-columns'),
               );
               if ( !$key || lc($key) ne lc($nibble_iter->nibble_index()) ) {
                  _die(ts("Cannot determine the key_len of the chunk index "
                     . "because MySQL chose "
                     . ($key ? "the $key" : "no") . " index "
                     . "instead of the " . $nibble_iter->nibble_index()
                     . " index for the first lower boundary statement.  "
                     . "See --[no]check-plan in the documentation for more "
                     . "information."), CANNOT_DETERMINE_KEY_SIZE);
               }
               elsif ( !$key_len ) {
                  _die(ts("The key_len of the $key index is "
                     . (defined $key_len ? "zero" : "NULL")
                     . ", but this should not be possible.  "
                     . "See --[no]check-plan in the documentation for more "
                     . "information."), INVALID_KEY_SIZE);
               }
               $tbl->{key_len} = $key_len;
            }
         }

         return 1; # continue nibbling table
      },
      next_boundaries => sub {
         my (%args) = @_;
         my $tbl         = $args{tbl};
         my $nibble_iter = $args{NibbleIterator};
         my $sth         = $nibble_iter->statements();
         my $boundary    = $nibble_iter->boundaries();

         return 0 if $o->get('dry-run');
         return 1 if $nibble_iter->one_nibble();

         # Check that MySQL will use the nibble index for the next upper
         # boundary sql.  This check applies to the next nibble.  So if
         # the current nibble number is 5, then nibble 5 is already done
         # and we're checking nibble number 6.
         # Skip if --nocheck-plan   See: https://bugs.launchpad.net/percona-toolkit/+bug/1340728
         if ( $o->get('check-plan') ) {
            my $expl = explain_statement(
               tbl  => $tbl,
               sth  => $sth->{explain_upper_boundary},
               vals => [ @{$boundary->{lower}}, $nibble_iter->limit() ],
            );
            if ( lc($expl->{key} || '') ne lc($nibble_iter->nibble_index() || '') ) {
               my $msg
                  = "Aborting copying table $tbl->{name} at chunk "
                  . ($nibble_iter->nibble_number() + 1)
                  . " because it is not safe to ascend.  Chunking should "
                  . "use the "
                  . ($nibble_iter->nibble_index() || '?')
                  . " index, but MySQL EXPLAIN reports that "
                  . ($expl->{key} ? "the $expl->{key}" : "no")
                  . " index will be used for "
                  . $sth->{upper_boundary}->{Statement}
                  . " with values "
                  . join(", ", map { defined $_ ? $_ : "NULL" }
                         (@{$boundary->{lower}}, $nibble_iter->limit()))
                  . "\n";
               _die(ts($msg), NOT_SAFE_TO_ASCEND);
            }
         }

         # Once nibbling begins for a table, control does not return to this
         # tool until nibbling is done because, as noted above, all work is
         # done in these callbacks.  This callback is the only place where we
         # can prematurely stop nibbling by returning false.  This allows
         # Ctrl-C to stop the tool between nibbles instead of between tables.
         return $oktorun; # continue nibbling table?
      },
      exec_nibble => sub {
         my (%args) = @_;
         my $tbl         = $args{tbl};
         my $nibble_iter = $args{NibbleIterator};

         return if $o->get('dry-run');

         # Count every chunk, even if it's ultimately skipped, etc.
         $tbl->{results}->{n_chunks}++;

         # Die unless the nibble is safe.
         nibble_is_safe(
            %args,
            OptionParser => $o,
         );

         # Exec and time the chunk checksum query.
         $tbl->{nibble_time} = exec_nibble(
            %args,
            tries   => $tries,
            Retry   => $retry,
            Quoter  => $q,
            stats   => \%stats,
         );
         PTDEBUG && _d('Nibble time:', $tbl->{nibble_time});

         # We're executing REPLACE queries which don't return rows.
         # Returning 0 from this callback causes the nibble iter to
         # get the next boundaries/nibble.
         return 0;
      },
      after_nibble => sub {
         my (%args) = @_;
         my $tbl         = $args{tbl};
         my $nibble_iter = $args{NibbleIterator};

         return unless $o->get('execute');

         # Update rate, chunk size, and progress if the nibble actually
         # selected some rows.
         my $cnt = $tbl->{row_cnt};
         if ( ($cnt || 0) > 0 ) {
            # Update the rate of rows per second for the entire server.
            # This is used for the initial chunk size of the next table.
            $total_rows += $cnt;
            $total_time += $tbl->{nibble_time};
            $avg_rate    = int($total_rows / $total_time);
            PTDEBUG && _d('Average copy rate (rows/s):', $avg_rate);

            # Adjust chunk size.  This affects the next chunk.
            if ( $chunk_time ) {
               # Calcuate a new chunk-size based on the rate of rows/s.
               $tbl->{chunk_size} = $tbl->{rate}->update(
                  $cnt,                # processed this many rows
                  $tbl->{nibble_time}, # is this amount of time
               );

               if ( $tbl->{chunk_size} < 1 ) {
                  # This shouldn't happen.  WeightedAvgRate::update() may
                  # return a value < 1, but minimum chunk size is 1.
                  $tbl->{chunk_size} = 1;

                  # This warning is printed once per table.
                  if ( !$tbl->{warned_slow} ) {
                     warn ts("Rows are copying very slowly.  "
                        . "--chunk-size has been automatically reduced to 1.  "
                        . "Check that the server is not being overloaded, "
                        . "or increase --chunk-time.  The last chunk "
                        . "selected $cnt rows and took "
                        . sprintf('%.3f', $tbl->{nibble_time})
                        . " seconds to execute.\n");
                     $tbl->{warned_slow} = 1;
                  }
               }

               # Update chunk-size based on the rate of rows/s.
               $nibble_iter->set_chunk_size($tbl->{chunk_size});
            }

            # Every table should have a Progress obj; update it.
            if ( my $tbl_pr = $tbl->{progress} ) {
               $tbl_pr->update( sub { return $total_rows } );
            }
         }

         # Wait forever for slaves to catch up.
         $replica_lag_pr->start() if $replica_lag_pr;
         $replica_lag->wait(Progress => $replica_lag_pr);

         # Wait forever for system load to abate.  wait() will die if
         # --critical load is reached.
         $sys_load_pr->start() if $sys_load_pr;
         $sys_load->wait(Progress => $sys_load_pr);

         # Wait forever for flow control to abate.
         $flow_ctl_pr->start() if $flow_ctl_pr;
         $flow_ctl->wait(Progress => $flow_ctl_pr) if $flow_ctl;

         # sleep between chunks to avoid overloading PXC nodes
         my $sleep = $args{NibbleIterator}->{OptionParser}->get('sleep');
         if ( $sleep ) {
            sleep $sleep;
         }

         return;
      },
      done => sub {
         if ( $o->get('execute') ) {
            print ts("Copied rows OK.\n");
         }
      },
   };

   # NibbleIterator combines these two statements and adds
   # "FROM $orig_table->{name} WHERE <nibble stuff>".
   my $dml = "INSERT LOW_PRIORITY IGNORE INTO $new_tbl->{name} "
           . "(" . join(', ', map { $q->quote($_->{new}) } @common_cols) . ") "
           . "SELECT";
   my $select = join(', ', map { $q->quote($_->{old}) } @common_cols);

   # The chunk size is auto-adjusted, so use --chunk-size as
   # the initial value, but then save and update the adjusted
   # chunk size in the table data struct.
   $orig_tbl->{chunk_size} = $o->get('chunk-size');

   # This won't (shouldn't) fail because we already verified in
   # check_orig_table() table we can NibbleIterator::can_nibble().
   my $nibble_iter = new NibbleIterator(
      Cxn                => $cxn,
      tbl                => $orig_tbl,
      chunk_size         => $orig_tbl->{chunk_size},
      chunk_index        => $o->get('chunk-index'),
      n_chunk_index_cols => $o->get('chunk-index-columns'),
      dml                => $dml,
      select             => $select,
      callbacks          => $callbacks,
      lock_in_share_mode => $lock_in_share_mode,
      OptionParser       => $o,
      Quoter             => $q,
      TableParser        => $tp,
      TableNibbler       => new TableNibbler(TableParser => $tp, Quoter => $q),
      comments           => {
         bite   => "pt-online-schema-change $PID copy table",
         nibble => "pt-online-schema-change $PID copy nibble",
      },
   );

   # Init a new weighted avg rate calculator for the table.
   $orig_tbl->{rate} = new WeightedAvgRate(target_t => $chunk_time);

   # Make a Progress obj for this table.  It may not be used;
   # depends on how many rows, chunk size, how fast the server
   # is, etc.  But just in case, all tables have a Progress obj.
   if ( $o->get('progress')
        && !$nibble_iter->one_nibble()
        &&  $nibble_iter->row_estimate() )
   {
      $orig_tbl->{progress} = new Progress(
         jobsize => $nibble_iter->row_estimate(),
         spec    => $o->get('progress'),
         name    => "Copying $orig_tbl->{name}",
      );
   }

   # --plugin hook
   if ( $plugin && $plugin->can('before_copy_rows') ) {
      $plugin->before_copy_rows();
   }

   # Start copying rows.  This may take awhile, but --progress is on
   # by default so there will be progress updates to stderr.
   eval {
      1 while $nibble_iter->next();
   };
   if ( $EVAL_ERROR ) {
      die ts("Error copying rows from $orig_tbl->{name} to "
        . "$new_tbl->{name}: $EVAL_ERROR");
   }
   $orig_tbl->{copied} = 1;  # flag for cleanup tasks

   # XXX Auto-choose the alter fk method BEFORE swapping/renaming tables
   # else everything will break because if drop_swap is chosen, then we
   # most NOT rename tables or drop the old table.
   if ( $alter_fk_method eq 'auto' ) {
      # If chunk time is set, then use the average rate of rows/s
      # from copying the orig table to determine the max size of
      # a child table that can be altered within one chunk time.
      # The limit is a fudge factor.  Chunk time won't be set if
      # the user specified --chunk-size=N on the cmd line, in which
      # case the max child table size is their specified chunk size
      # times the fudge factor.
      my $max_rows = $o->get('dry-run') ? $o->get('chunk-size') * $limit
            : $chunk_time && $avg_rate ? $avg_rate * $chunk_time * $limit
            : $o->get('chunk-size') * $limit;
      PTDEBUG && _d('Max allowed child table size:', $max_rows);

      $alter_fk_method = determine_alter_fk_method(
         child_tables => $child_tables,
         max_rows     => $max_rows,
         Cxn          => $cxn,
         OptionParser => $o,
      );

      if ( $alter_fk_method eq 'drop_swap' ) {
         $o->set('swap-tables',    0);
         $o->set('drop-old-table', 0);
      }
   }

   if (($vp->cmp('8.0') >= 0 && $vp->cmp('8.0.14') <= 0) && $vp->flavor() !~ m/maria/i && $alter_fk_method eq 'drop_swap') {
       my $msg = "--alter-foreign-keys-method=drop_swap doesn't work with MySQL 8.0+\n".
                 "See https://bugs.mysql.com/bug.php?id=89441";
       _die($msg, INVALID_PARAMETERS);
   }

   # --plugin hook
   if ( $plugin && $plugin->can('after_copy_rows') ) {
      $plugin->after_copy_rows();
   }
   if ( $o->get('preserve-triggers') ) {
       if ( !$o->get('swap-tables') && $o->get('drop-new-table') && !$o->get('alter-foreign-keys-method') eq "drop-swap" ) {
          print ts("Skipping triggers creation since --no-swap-tables was specified along with --drop-new-table\n");
      } else {
          print ts("Adding original triggers to new table.\n");
          foreach my $trigger_info (@$triggers_info) {
              next if ! ($trigger_info->{orig_triggers});
              foreach my $orig_trigger (@{$trigger_info->{orig_triggers}}) {
                  # if --no-swap-tables is used and --drop-new-table (default), then we don't do any trigger stuff
                  my $new_trigger_sqls;
                  eval {
                      # if --no-swap-tables is used and --no-drop-new-table is used, then we need to duplicate the trigger
                      my $duplicate_trigger = ( ! $o->get('swap-tables') && ! $o->get('drop-new-table') ) ? 1 : undef;

                      $new_trigger_sqls = create_trigger_sql(trigger => $orig_trigger,
                                                             db => $new_tbl->{db},
                                                             new_tbl => $new_tbl->{tbl},
                                                             orig_tbl => $orig_tbl->{tbl},
                                                             duplicate_trigger => $duplicate_trigger,
                                                            );
                  };
                  if ($EVAL_ERROR) {
                     _die("Cannot create triggers: $EVAL_ERROR", ERROR_CREATING_TRIGGERS);
                  }
                  next if !$o->get('execute');
                  PTDEBUG && _d('New triggers sqls');
                  for my $sql (@$new_trigger_sqls) {
                      PTDEBUG && _d($sql);
                      eval {
                          $cxn->dbh()->do($sql);
                      };
                      if ($EVAL_ERROR) {
                           _die("Exiting due to errors while restoring triggers: $EVAL_ERROR",
                               ERROR_RESTORING_TRIGGERS);
                      }
                  }
              }
          }
      }
   }

   # #####################################################################
   # Step 5: Update foreign key constraints if there are child tables.
   # #####################################################################
   if ( $child_tables ) {
      # --plugin hook
      if ( $plugin && $plugin->can('before_update_foreign_keys') ) {
         $plugin->before_update_foreign_keys();
      }

      eval {
         if ( $alter_fk_method eq 'none' ) {
            # This shouldn't happen, but in case it does we should know.
            warn "The tool detected child tables but "
               . "--alter-foreign-keys-method=none";
         }
         elsif ( $alter_fk_method eq 'rebuild_constraints' ) {
            rebuild_constraints(
               orig_tbl     => $new_tbl,
               old_tbl      => $orig_tbl,
               child_tables => $child_tables,
               OptionParser => $o,
               Quoter       => $q,
               Cxn          => $cxn,
               TableParser  => $tp,
               stats        => \%stats,
               Retry        => $retry,
               tries        => $tries,
            );
         }
         elsif ( $alter_fk_method eq 'drop_swap' ) {
            drop_swap(
               orig_tbl      => $orig_tbl,
               new_tbl       => $new_tbl,
               Cxn           => $cxn,
               OptionParser  => $o,
               stats         => \%stats,
               Retry         => $retry,
               tries         => $tries,
               analyze_table => $analyze_table,
            );
         }
         elsif ( !$alter_fk_method
               && $o->has('alter-foreign-keys-method')
               && ($o->get('alter-foreign-keys-method') || '') eq 'auto' ) {
            # If --alter-foreign-keys-method is 'auto' and we are on a dry run,
            # $alter_fk_method is left as an empty string.
            print "Not updating foreign key constraints because this is a dry run.\n";
         }
         else {
            # This should "never" happen because we check this var earlier.
            _die("Invalid --alter-foreign-keys-method: $alter_fk_method", INVALID_ALTER_FK_METHOD);
         }
      };
      if ( $EVAL_ERROR ) {
         $can_drop_triggers=undef;
         $oktorun=undef;
         _die("Error updating foreign key constraints: $EVAL_ERROR", ERROR_UPDATING_FKS);
      }

      # --plugin hook
      if ( $plugin && $plugin->can('after_update_foreign_keys') ) {
         $plugin->after_update_foreign_keys();
      }
   }

   # ########################################################################
   # Step 6: Swap tables
   # ########################################################################
   # --plugin hook
   if ( $plugin && $plugin->can('before_swap_tables') ) {
      $plugin->before_swap_tables();
   }

   my $old_tbl;
   if ( $o->get('swap-tables') ) {
      eval {
         $old_tbl = swap_tables(
            orig_tbl      => $orig_tbl,
            new_tbl       => $new_tbl,
            suffix        => '_old',
            Cxn           => $cxn,
            Quoter        => $q,
            OptionParser  => $o,
            Retry         => $retry,
            tries         => $tries,
            stats         => \%stats,
            analyze_table => $analyze_table,
         );
      };
      if ( $EVAL_ERROR ) {
         # TODO: one of these values can be undefined
         _die(ts("Error swapping tables: $EVAL_ERROR\n"
           . "To clean up, first verify that the original table "
           . "$orig_tbl->{name} has not been modified or renamed, "
           . "then drop the new table $new_tbl->{name} if it exists."),
              ERROR_SWAPPING_TABLES);
      }
   }

   $orig_tbl->{swapped} = 1;  # flag for cleanup tasks
   PTDEBUG && _d('Old table:', Dumper($old_tbl));

   # --plugin hook
   if ( $plugin && $plugin->can('after_swap_tables') ) {
      $plugin->after_swap_tables(
         old_tbl => $old_tbl,
      );
   }

   # ########################################################################
   # Step 7: Drop the old table.
   # ########################################################################
   if ( $o->get('drop-old-table') ) {
      if ( $o->get('dry-run') ) {
         print "Not dropping old table because this is a dry run.\n";
      }
      elsif ( !$old_tbl ) {
         print "Not dropping old table because --no-swap-tables was specified.\n";
      }
      else {
         # --plugin hook
         if ( $plugin && $plugin->can('before_drop_old_table') ) {
            $plugin->before_drop_old_table();
         }

         print ts("Dropping old table...\n");

         if ( $alter_fk_method eq 'none' ) {
            # Child tables still reference the old table, but the user
            # has chosen to break fks, so we need to disable fk checks
            # in order to drop the old table.
            my $sql = "SET foreign_key_checks=0";
            PTDEBUG && _d($sql);
            print $sql, "\n" if $o->get('print');
            $cxn->dbh()->do($sql);
         }

         my $sql = "DROP TABLE IF EXISTS $old_tbl->{name}";
         print $sql, "\n" if $o->get('print');
         PTDEBUG && _d($sql);
         eval {
            $cxn->dbh()->do($sql);
         };
         if ( $EVAL_ERROR ) {
            _die(ts("Error dropping the old table: $EVAL_ERROR\n"), ERROR_DROPPING_OLD_TABLE);
         }
         print ts("Dropped old table $old_tbl->{name} OK.\n");

         # --plugin hook
         if ( $plugin && $plugin->can('after_drop_old_table') ) {
            $plugin->after_drop_old_table();
         }
      }
   }
   elsif ( !$drop_triggers ) {
      print "Not dropping old table because --no-drop-triggers was specified.\n";
   }
   else {
      print "Not dropping old table because --no-drop-old-table was specified.\n";
   }

   # ########################################################################
   # Done.
   # ########################################################################

   $orig_tbl->{success} = 1;  # flag for cleanup tasks
   $cleanup = undef;          # exec cleanup tasks

   # --plugin hook
   if ( $plugin && $plugin->can('before_exit') ) {
      $plugin->before_exit(
         exit_status => $exit_status,
      );
   }

   return $exit_status;
}

# ############################################################################
# Subroutines.
# ############################################################################

sub validate_tries {
   my ($o) = @_;
   my @ops = qw(
      create_triggers
      drop_triggers
      copy_rows
      swap_tables
      update_foreign_keys
      analyze_table
   );
   my %user_tries;
   my $user_tries = $o->get('tries');
   if ( $user_tries ) {
      foreach my $var_val ( @$user_tries ) {
         my ($op, $tries, $wait) = split(':', $var_val);
         _die("Invalid --tries value: $var_val\n", INVALID_PARAMETERS) unless $op && $tries && $wait;
         _die("Invalid --tries operation: $op\n", INVALID_PARAMETERS) unless grep { $op eq $_ } @ops;
         _die("Invalid --tries tries: $tries\n", INVALID_PARAMETERS) unless $tries > 0;
         _die("Invalid --tries wait: $wait\n", INVALID_PARAMETERS) unless $wait > 0;
         $user_tries{$op} = {
            tries   => $tries,
            wait    => $wait,
         };
      }
   }

   my %default_tries;
   my $default_tries = $o->read_para_after(__FILE__, qr/MAGIC_tries/);
   if ( $default_tries ) {
      %default_tries = map {
         my $var_val = $_;
         my ($op, $tries, $wait) = $var_val =~ m/(\S+)/g;
         _die("Invalid --tries value: $var_val\n", INVALID_PARAMETERS) unless $op && $tries && $wait;
         _die("Invalid --tries operation: $op\n", INVALID_PARAMETERS) unless grep { $op eq $_ } @ops;
         _die("Invalid --tries tries: $tries\n", INVALID_PARAMETERS) unless $tries > 0;
         _die("Invalid --tries wait: $wait\n", INVALID_PARAMETERS) unless $wait > 0;
         $op => {
            tries => $tries,
            wait  => $wait,
         };
      } grep { m/^\s+\w+\s+\d+\s+[\d\.]+/ } split("\n", $default_tries);
   }

   my %tries = (
      %default_tries, # first the tool's defaults
      %user_tries,    # then the user's which overwrite the defaults
   );
   PTDEBUG && _d('--tries:', Dumper(\%tries));
   return \%tries;
}

sub check_alter {
   my (%args) = @_;
   my @required_args = qw(alter tbl dry_run Cxn TableParser OptionParser);
   foreach my $arg ( @required_args ) {
      die "I need a $arg argument" unless exists $args{$arg};
   }
   my ($alter, $tbl, $dry_run, $cxn, $tp, $o) = @args{@required_args};

   my $ok = 1;

   $alter =~ s/^(.*?)\s+COMMENT\s+'(.*?[^\\]')+(.*)/$1$3/;
   $alter =~ s/^(.*?)\s+COMMENT\s+"(.*?[^\\]")+(.*)/$1$3/;

   my $unique_fields = get_unique_index_fields($alter);

   if (scalar @$unique_fields && $o->get('check-unique-key-change')) {
       my $msg = "You are trying to add an unique key. This can result in data loss if the "
               . "data is not unique.\n"
               . "Please read the documentation for the --check-unique-key-change parameter.\n"
               . "You can check if the column(s) contain duplicate content "
               . "by running this/these query/queries:\n\n";
       foreach my $fields (@$unique_fields) {
           my $sql = "SELECT IF(COUNT(DISTINCT " . join(", ", @$fields) . ") = COUNT(*),\n"
                   . "       'Yes, the desired unique index currently contains only unique values', \n"
                   . "       'No, the desired unique index contains duplicated values. There will be data loss'\n"
                   . ") AS IsThereUniqueness FROM `$tbl->{db}`.`$tbl->{tbl}`;\n\n";
           $msg .= $sql;
        }
        $msg .= "Keep in mind that these queries could take a long time and consume a lot of resources\n\n";
        _die($msg, INVALID_PARAMETERS);
   }

   if ( ($tbl->{tbl_struct}->{engine} || '') =~ m/RocksDB/i ) {
       if ($alter =~ m/FOREIGN KEY/i) {
            my $msg = "FOREIGN KEYS are not supported by the RocksDB engine\n\n";
            _die($msg, UNSUPORTED_OPERATION);
       }
   }
   if ( $alter =~ m/Engine\s*=\s*["']?RocksDB["']?/i ) {
      my $row = $cxn->dbh()->selectrow_arrayref('SELECT @@binlog_format');
      if (scalar $row > 0 && $row->[0] eq 'STATEMENT') {
          _die("Cannot change engine to RocksDB while binlog_format is other than 'ROW'",
          UNSUPORTED_OPERATION);
      }
   }
   # ########################################################################
   # Check for DROP PRIMARY KEY.
   # ########################################################################
   if ( $alter =~ m/DROP\s+PRIMARY\s+KEY/i ) {
      my $msg = "--alter contains 'DROP PRIMARY KEY'.  Dropping and "
              . "altering the primary key can be dangerous, "
              . "especially if the original table does not have other "
              . "unique indexes.\n";
      if ( $dry_run ) {
         print $msg;
      }
      else {
         $ok = 0;
         warn $msg
            . "The tool should handle this correctly, but you should "
            . "test it first and carefully examine the triggers which "
            . "rely on the PRIMARY KEY or a unique index.  Specify "
            . "--no-check-alter to disable this check and perform the "
            . "--alter.\n";
      }
   }

   # ########################################################################
   # Check for renamed columns.
   # https://bugs.launchpad.net/percona-toolkit/+bug/1068562
   # ########################################################################
   my $renamed_cols = $args{renamed_cols};
   if ( %$renamed_cols ) {
      # sort is just for making output consistent for testing
      my $msg = "--alter appears to rename these columns:\n"
              . join("\n", map { "  $_ to $renamed_cols->{$_}" }
                           sort keys %$renamed_cols)
              . "\n";
      if ( $dry_run ) {
         print $msg;
      }
      else {
         $ok = 0;
         warn $msg
            . "The tool should handle this correctly, but you should "
            . "test it first because if it fails the renamed columns' "
            . "data will be lost!  Specify --no-check-alter to disable "
            . "this check and perform the --alter.\n";
      }
   }

   # ########################################################################
   # If it's a cluster node, check for MyISAM which does not work.
   # ########################################################################
   my $cluster = Percona::XtraDB::Cluster->new;
   if ( $cluster->is_cluster_node($cxn) ) {
      if ( ($tbl->{tbl_struct}->{engine} || '') =~ m/MyISAM/i ) {
         $ok = 0;
         warn $cxn->name . " is a cluster node and the table is MyISAM, "
            . "but MyISAM tables "
            . "do not work with clusters and this tool.  To alter the "
            . "table, you must manually convert it to InnoDB first.\n";
      }
      elsif ( $alter =~ m/ENGINE=MyISAM/i ) {
         $ok = 0;
         warn $cxn->name . " is a cluster node and the table is being "
            . "converted to MyISAM (ENGINE=MyISAM), but MyISAM tables "
            . "do not work with clusters and this tool.  To alter the "
            . "table, you must manually convert it to InnoDB first.\n";
      }
   }

   if ( !$ok ) {
      # check_alter.t relies on this output.
      _die("--check-alter failed.\n", UNSUPORTED_OPERATION);
   }

   return;
}

sub _has_self_ref_fks {
    my ($orig_db, $orig_table, $child_tables) = @_;

    my $db_tbl = sprintf('`%s`.`%s`', $orig_db, $orig_table);

    foreach my $child_table ( @$child_tables ) {
        if ("$db_tbl" eq "$child_table->{name}") {
             return 1;
         }
    }

    return 0;
}

# This function tries to detect if the --alter param is adding unique indexes.
# It returns an array of arrays, having a list of fields for each unique index
# found.
# Example:
# Input string: add i int comment "first comment ", ADD UNIQUE INDEX (C1) comment
#               'second comment', CREATE UNIQUE INDEX C ON T1 (C2, c3) comment "third"
#
# Output:
# $VAR1 = [
#           [ 'C1' ],
#           [ 'C2', 'c3' ]
#         ];
#
# Thse fields are used to build an example SELECT to detect if currently there are
# rows that will produce duplicates when the new UNIQUE INDEX is created.

sub get_unique_index_fields {
   my ($alter) = @_;
   my $remove_comments_re = qr/(.*?\s+)?comment ('.*?'|".*?")(.*)/i;

   $alter =~ s/\\"//g; # Remove \" just to make remove_comments_re easier

   my $clean;
   my $suffix = $alter;

   while ($alter =~ /$remove_comments_re/g) {
       $clean .= $1;
       $suffix = $3;
   }
   $clean .= $suffix;

   my $fields = [];
   my $fields_re = qr/\s(?:PRIMARY|UNIQUE)\s+(?:INDEX|KEY|)\s*(?:.*?)\s*\((.*?)\)/i;

   while($clean =~ /$fields_re/g) {
      push @$fields, [ split /\s*,\s*/, $1 ];
   }

   return $fields;
}

sub find_renamed_cols {
   my (%args) = @_;
   my @required_args = qw(alter TableParser);
   foreach my $arg ( @required_args ) {
      die "I need a $arg argument" unless $args{$arg};
   }
   my ($alter, $tp) = @args{@required_args};

   my $unquoted_ident = qr/
      (?!\p{Digit}+[.\s])            # Not all digits
      [0-9a-zA-Z_\x{80}-\x{FFFF}\$]+ # As per the spec
   /x;

   my $quoted_ident = do {
      my $quoted_ident_character = qr/
         [\x{01}-\x{5F}\x{61}-\x{FFFF}] # Any character but the null byte and `
      /x;
      qr{
         # The following alternation is there because something like (?<=.)
         # would match if this regex was used like /.$re/,
         # or even more tellingly, would match on "``" =~ /`$re`/
         $quoted_ident_character+        # One or more characters
         (?:``$quoted_ident_character*)* # possibly followed by `` and
                                         # more characters, zero or more times
         |$quoted_ident_character*         # OR, zero or more characters
          (?:``$quoted_ident_character* )+ # Followed by `` and maybe more
                                           # characters, one or more times.
      }x
   };

   my $ansi_quotes_ident = qr/
            [^"]+ (?: "" [^"]* )*
         |  [^"]* (?: "" [^"]* )+
   /x;

   my $table_ident  = qr/$unquoted_ident|`$quoted_ident`|"$ansi_quotes_ident"/;

   # remove comments
   $alter =~ s/^(.*?)\s+COMMENT\s+'(.*?[^\\]')+(.*)/$1$3/;
   $alter =~ s/^(.*?)\s+COMMENT\s+"(.*?[^\\]")+(.*)/$1$3/;

   my $alter_change_col_re = qr/\bCHANGE \s+ (?:COLUMN \s+)?
                                ($table_ident) \s+ ($table_ident)/ix;

   my %renames;
   while ( $alter =~ /$alter_change_col_re/g ) {
      my ($orig, $new) = map { $tp->ansi_to_legacy($_) } $1, $2;
      next unless $orig && $new;
      my (undef, $orig_tbl) = Quoter->split_unquote($orig);
      my (undef, $new_tbl)  = Quoter->split_unquote($new);
      # Silly but plausible: CHANGE COLUMN same_name same_name ...
      next if lc($orig_tbl) eq lc($new_tbl);
      $renames{lc($orig_tbl)} = $new_tbl;
   }
   PTDEBUG && _d("Renamed columns (old => new): ", Dumper(\%renames));
   return \%renames;
}

sub nibble_is_safe {
   my (%args) = @_;
   my @required_args = qw(Cxn tbl NibbleIterator OptionParser);
   foreach my $arg ( @required_args ) {
      die "I need a $arg argument" unless $args{$arg};
   }
   my ($cxn, $tbl, $nibble_iter, $o)= @args{@required_args};

   # EXPLAIN the checksum chunk query to get its row estimate and index.
   # XXX This call and others like it are relying on a Perl oddity.
   # See https://bugs.launchpad.net/percona-toolkit/+bug/987393
   my $sth      = $nibble_iter->statements();
   my $boundary = $nibble_iter->boundaries();
   my $expl     = explain_statement(
      tbl  => $tbl,
      sth  => $sth->{explain_nibble},
      vals => [ @{$boundary->{lower}}, @{$boundary->{upper}} ],
   );

   # Ensure that MySQL is using the chunk index if the table is being chunked.
   # Skip if --nocheck-plan   See: https://bugs.launchpad.net/percona-toolkit/+bug/1340728
      if ( !$nibble_iter->one_nibble()
           && lc($expl->{key} || '') ne lc($nibble_iter->nibble_index() || '')
           && $o->get('check-plan') )
      {
         die ts("Error copying rows at chunk " . $nibble_iter->nibble_number()
            . " of $tbl->{db}.$tbl->{tbl} because MySQL chose "
            . ($expl->{key} ? "the $expl->{key}" : "no") . " index "
            . " instead of the " . $nibble_iter->nibble_index() . "index.\n");
      }

   # Ensure that the chunk isn't too large if there's a --chunk-size-limit.
   # If single-chunking the table, this has already been checked, so it
   # shouldn't have changed.  If chunking the table with a non-unique key,
   # oversize chunks are possible.
   if ( my $limit = $o->get('chunk-size-limit') ) {
      my $oversize_chunk
         = $limit ? ($expl->{rows} || 0) >= $tbl->{chunk_size} * $limit
         :          0;
      if ( $oversize_chunk
           && $nibble_iter->identical_boundaries($boundary->{upper},
                                                 $boundary->{next_lower}) )
      {
         die ts("Error copying rows at chunk " . $nibble_iter->nibble_number()
            . " of $tbl->{db}.$tbl->{tbl} because it is oversized.  "
            . "The current chunk size limit is "
            . ($tbl->{chunk_size} * $limit)
            . " rows (chunk size=$tbl->{chunk_size}"
            . " * chunk size limit=$limit), but MySQL estimates "
            . "that there are " . ($expl->{rows} || 0)
            . " rows in the chunk.\n");
      }
   }

   # Ensure that MySQL is still using the entire index.
   # https://bugs.launchpad.net/percona-toolkit/+bug/1010232
   # Skip if --nocheck-plan   See: https://bugs.launchpad.net/percona-toolkit/+bug/1340728
   if ( !$nibble_iter->one_nibble()
        && $tbl->{key_len}
        && ($expl->{key_len} || 0) < $tbl->{key_len}
        && $o->get('check-plan') )
   {
      die ts("Error copying rows at chunk " . $nibble_iter->nibble_number()
         . " of $tbl->{db}.$tbl->{tbl} because MySQL used "
         . "only " . ($expl->{key_len} || 0) . " bytes "
         . "of the " . ($expl->{key} || '?') . " index instead of "
         . $tbl->{key_len} . ".  See the --[no]check-plan documentation "
         . "for more information.\n");
   }

   return 1; # safe
}

sub create_new_table {
   my (%args) = @_;
   my @required_args = qw(new_table_name orig_tbl Cxn Quoter OptionParser TableParser);
   foreach my $arg ( @required_args ) {
      die "I need a $arg argument" unless $args{$arg};
   }
   my ($new_table_name, $orig_tbl, $cxn, $q, $o, $tp) = @args{@required_args};
   my $new_table_prefix = $args{new_table_prefix};

   # Get the original table struct.
   my $ddl = $tp->get_create_table(
      $cxn->dbh(),
      $orig_tbl->{db},
      $orig_tbl->{tbl},
   );

   $new_table_name =~ s/%T/$orig_tbl->{tbl}/;

   print "Creating new table...\n";
   my $tries = $new_table_prefix ? 10 : 1;
   my $tryno = 1;
   my @old_tables;
   while ( $tryno++ <= $tries ) {
      if ( $new_table_prefix ) {
         $new_table_name = $new_table_prefix . $new_table_name;
      }

      if ( length($new_table_name) > 64 ) {
         my $truncated_table_name = substr($new_table_name, 0, 64);
         PTDEBUG && _d($new_table_name, 'is over 64 characters long, '
            . 'truncating to', $truncated_table_name);
         $new_table_name = $truncated_table_name;
      }

      # Generate SQL to create the new table.  We do not use CREATE TABLE LIKE
      # because it doesn't preserve foreign key constraints. Here we need to
      # rename the FK constraints, too. This is because FK constraints are
      # internally stored as <database>.<constraint> and there cannot be
      # duplicates.  If we don't rename the constraints, then InnoDB will throw
      # error 121 (duplicate key violation) when we try to execute the CREATE
      # TABLE.  TODO: this code isn't perfect. If we rename a constraint from
      # foo to _foo and there is already a constraint with that name in this
      # or another table, we can still have a collision. But if there are
      # multiple FKs on this table, it's hard to know which one is causing the
      # trouble. Should we generate random/UUID FK names or something instead?
      my $quoted = $q->quote($orig_tbl->{db}, $new_table_name);
      my $sql    = $ddl;
      $sql       =~ s/\ACREATE TABLE .*?\($/CREATE TABLE $quoted (/m;


      # When the new temp table is created, we need to avoid collisions on constraint names
      # This is in contrast to previous behavior were we added underscores
      # indefinitely, sometimes exceeding the allowed name limit
      # https://bugs.launchpad.net/percona-toolkit/+bug/1215587
      # So we do replacements when constraint names:
      # Has 2 _, we remove them
      # Has 1 _, we add one to make 2
      # Has no _, we add one to make 1
      # This gives on more salt where the FK names have been previously been altered
      # https://bugs.launchpad.net/percona-toolkit/+bug/1632522
      my %search_dict = (
        'CONSTRAINT `__' => 'CONSTRAINT `',
        'CONSTRAINT `_' => 'CONSTRAINT `__',
        'CONSTRAINT `' => 'CONSTRAINT `_'
      );
      my $constraint_pattern = qr((CONSTRAINT `__|CONSTRAINT `_|CONSTRAINT `));
      $sql =~ s/$constraint_pattern/$search_dict{$1}/gm;
      # Limit constraint name to 64 characters
      $sql =~ s/CONSTRAINT `([^`]{1,64})[^`]*` (.*)/  CONSTRAINT `$1` $2/gm;

      if ( $o->get('default-engine') ) {
         $sql =~ s/\s+ENGINE=\S+//;
      }
      if ( $o->get('data-dir') && !$o->got('remove-data-dir') ) {
          if ( (-d $o->get('data-dir')) && (-w $o->get('data-dir')) ){
             $sql = insert_data_directory($sql, $o->get('data-dir'));
             PTDEBUG && _d("adding data dir ".$o->get('data-dir'));
             PTDEBUG && _d("New query\n$sql\n");
          } else {
              die $o->get('data-dir') . " is not a directory or it is not writable";
          }
      }
      if ( $o->got('remove-data-dir') ) {
         $sql =~ s/DATA DIRECTORY\s*=\s*'.*?'//;
         PTDEBUG && _d("removing data dir");
      }
      PTDEBUG && _d($sql);
      eval {
         $cxn->dbh()->do($sql);
      };
      if ( $EVAL_ERROR ) {
         # Ignore this error because if multiple instances of the tool
         # are running, or previous runs failed and weren't cleaned up,
         # then there will be other similarly named tables with fewer
         # leading prefix chars.  Or, in rarer cases, the db just happens
         # to have a similarly named table created by the user for other
         # purposes.
         if ( $EVAL_ERROR =~ m/table.+?already exists/i ) {
            push @old_tables, $q->quote($orig_tbl->{db}, $new_table_name);
            next;
         }

         # Some other error happened.  Let the caller catch it.
         die $EVAL_ERROR;
      }
      print $sql, "\n" if $o->get('print');  # the sql that work
      print "Created new table $orig_tbl->{db}.$new_table_name OK.\n";
      return { # success
         db   => $orig_tbl->{db},
         tbl  => $new_table_name,
         name => $q->quote($orig_tbl->{db}, $new_table_name),
      };
   }

   die "Failed to find a unique new table name after $tries attemps.  "
     . "The following tables exist which may be left over from previous "
     . "failed runs of the tool:\n"
     . join("\n", map { "  $_" } @old_tables)
     . "\nExamine these tables and drop some or all of them if they are "
     . "no longer need, then re-run the tool.\n";
}

sub insert_data_directory {
    my ($sql, $data_dir) = @_;
    $sql =~ s/DATA DIRECTORY\s*=\s*'.*?'//;

    my $re_ps=qr/(\/\*!50100 )?(PARTITION|SUBPARTITION)/;

    if ($sql=~ m/$re_ps/) {
        my $insert_pos=$-[0];
        $sql = substr($sql, 0, $insert_pos - 1). " DATA DIRECTORY = '$data_dir' " .substr($sql, $insert_pos);
    } else {
        $sql .= " DATA DIRECTORY = '$data_dir' ";
    }
    return $sql;
}

sub swap_tables {
   my (%args) = @_;
   my @required_args = qw(orig_tbl new_tbl Cxn Quoter OptionParser Retry tries stats);
   foreach my $arg ( @required_args ) {
      die "I need a $arg argument" unless $args{$arg};
   }
   my ($orig_tbl, $new_tbl, $cxn, $q, $o, $retry, $tries, $stats) = @args{@required_args};

   my $prefix       = '_';
   my $table_name   = $orig_tbl->{tbl} . ($args{suffix} || '');
   my $name_tries   = 20;  # don't try forever
   my $table_exists = qr/table.+?already exists/i;

   # This sub only works for --execute.  Since the options are
   # mutually exclusive and we return in the if case, the elsif
   # is just a paranoid check because swapping the tables is one
   # of the most sensitive/dangerous operations.
   if ( $o->get('dry-run') ) {
      print "Not swapping tables because this is a dry run.\n";

      # A return value really isn't needed, but this trick allows
      # rebuild_constraints() to parse and show the sql statements
      # it would used.  Otherwise, this has no effect.
      return $orig_tbl;
   }
   elsif ( $o->get('execute') ) {
      # ANALYZE TABLE before renaming to update InnoDB optimizer statistics.
      # https://bugs.launchpad.net/percona-toolkit/+bug/1491261
      if ( $args{analyze_table} ) {
         print ts("Analyzing new table...\n");
         my $sql_analyze = "ANALYZE TABLE $new_tbl->{name} /* pt-online-schema-change */";
         osc_retry(
            Cxn     => $cxn,
            Retry   => $retry,
            tries   => $tries->{analyze_table},
            stats   => $stats,
            code    => sub {
               PTDEBUG && _d($sql_analyze);
               $cxn->dbh()->do($sql_analyze);
            },
         );
      }

      print ts("Swapping tables...\n");
      while ( $name_tries-- ) {

         # https://bugs.launchpad.net/percona-toolkit/+bug/1526105
         if ( $name_tries <= 10 ) { # we've already added 10 underscores?
            # time to try a small random string
            my @chars = ("A".."Z", "0".."9");
            $prefix = '';
            $prefix .= $chars[rand @chars] for 1..6;
            $prefix .= "_";
         }

         $table_name = $prefix . $table_name;

         if ( length($table_name) > 64 ) {
            my $truncated_table_name = substr($table_name, 0, 64);
            PTDEBUG && _d($table_name, 'is > 64 chars, truncating to',
                          $truncated_table_name);
            $table_name = $truncated_table_name;
         }

         my $sql = "RENAME TABLE $orig_tbl->{name} "
                 . "TO " . $q->quote($orig_tbl->{db}, $table_name)
                 . ", $new_tbl->{name} TO $orig_tbl->{name}" ;

         eval {
            osc_retry(
               Cxn     => $cxn,
               Retry   => $retry,
               tries   => $tries->{swap_tables},
               stats   => $stats,
               code    => sub {
                  PTDEBUG && _d($sql);
                  $cxn->dbh()->do($sql);
               },
               ignore_errors => [
                  # Ignore this error because if multiple instances of the tool
                  # are running, or previous runs failed and weren't cleaned up,
                  # then there will be other similarly named tables with fewer
                  # leading prefix chars.  Or, in rare cases, the db happens
                  # to have a similarly named table created by the user for
                  # other purposes.
                  $table_exists,
               ],
               operation => "swap_tables",
            );
         };
         if ( my $e = $EVAL_ERROR ) {
            if ( $e =~ $table_exists ) {
               PTDEBUG && _d($e);
               next;
            }
            die ts($e); # Don't replace this by _die
         }

         print $sql, "\n" if $o->get('print');
         print ts("Swapped original and new tables OK.\n");

         return { # success
            db   => $orig_tbl->{db},
            tbl  => $table_name,
            name => $q->quote($orig_tbl->{db}, $table_name),
         };
      }

      # This shouldn't happen.
      die ts("Failed to find a unique old table name after "
         . "serveral attempts.\n");
   }
}

sub check_orig_table {
   my ( %args ) = @_;
   my @required_args = qw(orig_tbl Cxn TableParser OptionParser Quoter);
   foreach my $arg ( @required_args ) {
      die "I need a $arg argument" unless $args{$arg};
   }
   my ($orig_tbl, $cxn, $tp, $o, $q) = @args{@required_args};

   my $dbh = $cxn->dbh();

   # The original table must exist, of course.
   if (!$tp->check_table(dbh=>$dbh,db=>$orig_tbl->{db},tbl=>$orig_tbl->{tbl})) {
      die "The original table $orig_tbl->{name} does not exist.\n";
   }

   my ( $version ) = $dbh->selectrow_array("SELECT VERSION()");
   # There cannot be any triggers on the original table.
   my $sql = 'SHOW TRIGGERS FROM ' . $q->quote($orig_tbl->{db})
           . ' LIKE ' . $q->literal_like($orig_tbl->{tbl});
   PTDEBUG && _d($sql);
   my $triggers = $dbh->selectall_arrayref($sql);
   if ( $triggers && @$triggers ) {
       if ( VersionCompare::cmp($version, '5.7.0') < 0  && VersionCompare::cmp($version, '10.0.0') <= 0) {
           die "The table $orig_tbl->{name} has triggers.  This tool "
             . "needs to create its own triggers, so the table cannot "
             . "already have triggers.\n";
       } elsif ( ( VersionCompare::cmp($version, '5.7.0') >= 0 || VersionCompare::cmp($version, '10.0.0') >0 )
                 && !$o->get('preserve-triggers') ) {
           die "The table $orig_tbl->{name} has triggers but --preserve-triggers was not specified.\n"
             . "Please read the documentation for --preserve-triggers.\n";
       }
   }

   # Get the table struct.  NibbleIterator needs this, and so do we.
   my $ddl = $tp->get_create_table(
      $cxn->dbh(),
      $orig_tbl->{db},
      $orig_tbl->{tbl},
   );
   $orig_tbl->{tbl_struct} = $tp->parse($ddl);

   # Must be able to nibble the original table (to copy rows to the new table).
   eval {
      NibbleIterator::can_nibble(
         Cxn          => $cxn,
         tbl          => $orig_tbl,
         chunk_size   => $o->get('chunk-size'),
         chunk_indx   => $o->get('chunk-index'),
         OptionParser => $o,
         TableParser  => $tp,
      );
   };
   if ( $EVAL_ERROR ) {
      die "Cannot chunk the original table $orig_tbl->{name}: $EVAL_ERROR\n";
   }

   return;  # success
}

sub find_child_tables {
   my ( %args ) = @_;
   my @required_args = qw(tbl Cxn Quoter);
   foreach my $arg ( @required_args ) {
      die "I need a $arg argument" unless $args{$arg};
   }
   my ($tbl, $cxn, $q) = @args{@required_args};

   if ( lc($tbl->{tbl_struct}->{engine} || '') eq 'myisam' ) {
      PTDEBUG && _d(q{MyISAM table, not looking for child tables});
      return;
   }

   PTDEBUG && _d('Finding child tables');

   my $sql = "SELECT table_schema, table_name "
           . "FROM information_schema.key_column_usage "
           . "WHERE referenced_table_schema='$tbl->{db}' "
           . "AND referenced_table_name='$tbl->{tbl}'";

   if ($args{only_same_schema_fks}) {
       $sql .= " AND table_schema='$tbl->{db}'";
   }

   PTDEBUG && _d($sql);
   my $rows = $cxn->dbh()->selectall_arrayref($sql);
   if ( !$rows || !@$rows ) {
      PTDEBUG && _d('No child tables found');
      return;
   }

   my @child_tables;
   foreach my $row ( @$rows ) {
      my $tbl = {
         db   => $row->[0],
         tbl  => $row->[1],
         name => $q->quote(@$row),
      };

      # Get row estimates for each child table so we can give the user
      # some input on choosing an --alter-foreign-keys-method if they
      # don't use "auto".
      my ($n_rows) = NibbleIterator::get_row_estimate(
         Cxn => $cxn,
         tbl => $tbl,
      );
      $tbl->{row_est} = $n_rows;

      push @child_tables, $tbl;
   }

   PTDEBUG && _d('Child tables:', Dumper(\@child_tables));
   return \@child_tables;
}

sub determine_alter_fk_method {
   my ( %args ) = @_;
   my @required_args = qw(child_tables max_rows Cxn OptionParser);
   foreach my $arg ( @required_args ) {
      die "I need a $arg argument" unless $args{$arg};
   }
   my ($child_tables, $max_rows, $cxn, $o) = @args{@required_args};

   if ( $o->get('dry-run') ) {
      print "Not determining the method to update foreign keys "
         . "because this is a dry run.\n";
      return '';  # $alter_fk_method can't be undef
   }

   # The rebuild_constraints method is the default becuase it's safer
   # and doesn't cause the orig table to go missing for a moment.
   my $method = 'rebuild_constraints';

   print ts("Max rows for the rebuild_constraints method: $max_rows\n"
      . "Determining the method to update foreign keys...\n");
   foreach my $child_tbl ( @$child_tables ) {
      print ts("  $child_tbl->{name}: ");
      my ($n_rows) = NibbleIterator::get_row_estimate(
         Cxn   => $cxn,
         tbl   => $child_tbl,
      );
      if ( $n_rows > $max_rows ) {
         print "too many rows: $n_rows; must use drop_swap\n";
         $method = 'drop_swap';
         last;
      }
      else {
         print "$n_rows rows; can use rebuild_constraints\n";
      }
   }

   return $method || '';  # $alter_fk_method can't be undef
}

sub rebuild_constraints {
   my ( %args ) = @_;
   my @required_args = qw(orig_tbl old_tbl child_tables stats
                          Cxn Quoter OptionParser TableParser
                          Retry tries);
   foreach my $arg ( @required_args ) {
      die "I need a $arg argument" unless $args{$arg};
   }
   my ($orig_tbl, $old_tbl, $child_tables, $stats, $cxn, $q, $o, $tp, $retry, $tries)
      = @args{@required_args};

   # MySQL has a "feature" where if the parent tbl is in the same db,
   # then the child tbl ref is simply `parent_tbl`, but if the parent tbl
   # is in another db, then the child tbl ref is `other_db`.`parent_tbl`.
   # When we recreate the ref below, we use the db-qualified form, and
   # MySQL will automatically trim the db if the tables are in the same db.
   my $quoted_old_table = $q->quote($old_tbl->{tbl});
   my $constraint       = qr/
      ^\s+
      (
         CONSTRAINT.+?
         REFERENCES\s(?:$quoted_old_table|$old_tbl->{name})
         .+
      )$
   /xm;
   PTDEBUG && _d('Rebuilding fk constraint matching', $constraint);

   if ( $o->get('dry-run') ) {
      print "Not rebuilding foreign key constraints because this is a dry run.\n";
   }
   else {
      print ts("Rebuilding foreign key constraints...\n");
   }

   CHILD_TABLE:
   foreach my $child_tbl ( @$child_tables ) {
      my $table_def = $tp->get_create_table(
         $cxn->dbh(),
         $child_tbl->{db},
         $child_tbl->{tbl},
      );
      my @constraints = $table_def =~ m/$constraint/g;
      if ( !@constraints ) {
         warn ts("$child_tbl->{name} has no foreign key "
            . "constraints referencing $old_tbl->{name}.\n");
         next CHILD_TABLE;
      }

      my @rebuilt_constraints;
      foreach my $constraint ( @constraints ) {
         PTDEBUG && _d('Rebuilding fk constraint:', $constraint);

         # Remove trailing commas in case there are multiple constraints on the
         # table.
         $constraint =~ s/,$//;

         # Find the constraint name. It will be quoted already.
         my ($fk) = $constraint =~ m/CONSTRAINT\s+`([^`]+)`/;

         # Drop the reference to the old table/renamed orig table, and add a new
         # reference to the new table.  InnoDB will throw an error if the new
         # constraint has the same name as the old one, so we must rename it.
         # Example: after renaming sakila.actor to sakila.actor_old (for
         # example), the foreign key on film_actor looks like this:
         # CONSTRAINT `fk_film_actor_actor` FOREIGN KEY (`actor_id`) REFERENCES
         #   `actor_old` (`actor_id`) ON UPDATE CASCADE
         # We need it to look like this instead:
         # CONSTRAINT `_fk_film_actor_actor` FOREIGN KEY (`actor_id`) REFERENCES
         #   `actor` (`actor_id`) ON UPDATE CASCADE
         # Reference the correct table name...
         $constraint =~ s/REFERENCES[^\(]+/REFERENCES $orig_tbl->{name} /;

         # And rename the constraint to avoid conflict
         # If it has a leading underscore, we remove one, otherwise we add one
         # This is in contrast to previous behavior were we added underscores
         # indefinitely, sometimes exceeding the allowed name limit
         # https://bugs.launchpad.net/percona-toolkit/+bug/1215587
         # Add one more salt to renaming FK constraint names
         # This will add 2 _ to a self referencing FK thus avoiding a duplicate key constraint
         # https://bugs.launchpad.net/percona-toolkit/+bug/1632522
         my $new_fk;
         if ($fk =~ /^__/) {
           ($new_fk = $fk) =~ s/^__//;
         } else {
           $new_fk = '_'.$fk;
           if(length $new_fk > 64) {
             substr($new_fk, 64 - length $new_fk) = '';
           }
         }

         PTDEBUG && _d("Old FK name: $fk New FK name: $new_fk");

         $constraint =~ s/CONSTRAINT `$fk`/CONSTRAINT `$new_fk`/;

         my $sql = "DROP FOREIGN KEY `$fk`, "
                 . "ADD $constraint";
         push @rebuilt_constraints, $sql;
      }

      my $sql = "ALTER TABLE $child_tbl->{name} "
              . join(', ', @rebuilt_constraints);
      print $sql, "\n" if $o->get('print');
      if ( $o->get('execute') ) {
         osc_retry(
            Cxn     => $cxn,
            Retry   => $retry,
            tries   => $tries->{update_foreign_keys},
            stats   => $stats,
            code    => sub {
               PTDEBUG && _d("SET foreign_key_checks=0");
               $cxn->dbh()->do("SET foreign_key_checks=0");
	       PTDEBUG && _d($sql);
               $cxn->dbh()->do($sql);
	       PTDEBUG && _d("SET foreign_key_checks=1");
               $cxn->dbh()->do("SET foreign_key_checks=1");
               $stats->{rebuilt_constraint}++;
            },
         );
      }
   }

   if ( $o->get('execute') ) {
      print ts("Rebuilt foreign key constraints OK.\n");
   }

   return;
}

sub drop_swap {
   my ( %args ) = @_;
   my @required_args = qw(orig_tbl new_tbl Cxn OptionParser stats Retry tries);
   foreach my $arg ( @required_args ) {
      die "I need a $arg argument" unless $args{$arg};
   }
   my ($orig_tbl, $new_tbl, $cxn, $o, $stats, $retry, $tries) = @args{@required_args};

   if ( $o->get('dry-run') ) {
      print "Not drop-swapping tables because this is a dry run.\n";
   }
   else {
      print ts("Drop-swapping tables...\n");
   }

   # ANALYZE TABLE before renaming to update InnoDB optimizer statistics.
   # https://bugs.launchpad.net/percona-toolkit/+bug/1491261
   if ( $args{analyze_table} ) {
      print ts("Analyzing new table...\n");
      my $sql_analyze = "ANALYZE TABLE $new_tbl->{name} /* pt-online-schema-change */";
      osc_retry(
         Cxn     => $cxn,
         Retry   => $retry,
         tries   => $tries->{analyze_table},
         stats   => $stats,
         code    => sub {
            PTDEBUG && _d($sql_analyze);
            $cxn->dbh()->do($sql_analyze);
         },
      );
   }

   my @sqls = (
      "SET foreign_key_checks=0",
      "DROP TABLE IF EXISTS $orig_tbl->{name}",
      "RENAME TABLE $new_tbl->{name} TO $orig_tbl->{name}",
   );

   # we don't want to be interrupted during the swap!
   # since it might leave original table dropped
   # https://bugs.launchpad.net/percona-toolkit/+bug/1368244
   $dont_interrupt_now = 1;

   foreach my $sql ( @sqls ) {
      PTDEBUG && _d($sql);
      print $sql, "\n" if $o->get('print');
      if ( $o->get('execute') ) {
         osc_retry(
            Cxn     => $cxn,
            Retry   => $retry,
            tries   => $tries->{update_foreign_keys},
            stats   => $stats,
            code    => sub {
               PTDEBUG && _d($sql);
               $cxn->dbh()->do($sql);
            },
         );
      }
   }

   $dont_interrupt_now = 0;

   if ( $o->get('execute') ) {
      print ts("Dropped and swapped tables OK.\n");
   }

   return;
}

sub create_triggers {
   my ( %args ) = @_;
   my @required_args = qw(orig_tbl new_tbl del_tbl columns Cxn Quoter OptionParser Retry tries stats);
   foreach my $arg ( @required_args ) {
      die "I need a $arg argument" unless $args{$arg};
   }
   my ($orig_tbl, $new_tbl, $del_tbl, $cols, $cxn, $q, $o, $retry, $tries, $stats) = @args{@required_args};

   # This sub works for --dry-run and --execute.  With --dry-run it's
   # only interesting if --print is specified, too; then the user can
   # see the create triggers statements for --execute.
   if ( $o->get('dry-run') ) {
      print "Not creating triggers because this is a dry run.\n";
   }
   else {
      print ts("Creating triggers...\n");
   }

   # Create a unique trigger name prefix based on the orig table name
   # so multiple instances of the tool can run on different tables.
   my $pp = $args{reverse_triggers} ? "rt_" : '';
   my $prefix = $pp.'pt_osc_' . $orig_tbl->{db} . '_' . $orig_tbl->{tbl};
   $prefix   =~ s/\W/_/g;

   if ( length($prefix) > 60 ) {
      my $truncated_prefix = substr($prefix, 0, 60);
      PTDEBUG && _d('Trigger prefix', $prefix, 'is over 60 characters long,',
                     'truncating to', $truncated_prefix);
      $prefix = $truncated_prefix;
   }

   # To be safe, the delete trigger must specify all the columns of the
   # primary key/unique index.  We use null-safe equals, because unique
   # unique indexes can be nullable.  Cols are from the new table and
   # they may have been renamed
   my %old_col_for    = map { $_->{new} => $_->{old} } @$cols;
   my $tbl_struct     = $del_tbl->{tbl_struct};

   # ---------------------------------------------------------------------------------------
   my $del_index      = $del_tbl->{del_index};
   my $del_index_cols = join(" AND ", map {
      my $new_col  = $_;
      my $old_col  = $old_col_for{$new_col} || $new_col;
      my $new_qcol = $q->quote($new_col);
      my $old_qcol = $q->quote($old_col);
      "$new_tbl->{name}.$new_qcol <=> OLD.$old_qcol"
   } @{$tbl_struct->{keys}->{$del_index}->{cols}} );

   my $delete_trigger
      = "CREATE TRIGGER `${prefix}_del` AFTER DELETE ON $orig_tbl->{name} "
      . "FOR EACH ROW "
      . "BEGIN "
      . "DECLARE CONTINUE HANDLER FOR 1146 begin end; "
      . "DELETE IGNORE FROM $new_tbl->{name} "
      . "WHERE $del_index_cols; "
      . "END ";

   # ---------------------------------------------------------------------------------------
   my $qcols    = join(', ', map { $q->quote($_->{new}) }        @$cols);
   my $new_vals = join(', ', map { "NEW.".$q->quote($_->{old}) } @$cols);

   my $insert_trigger
      = "CREATE TRIGGER `${prefix}_ins` AFTER INSERT ON $orig_tbl->{name} "
      . "FOR EACH ROW "
      . "BEGIN "
      . "DECLARE CONTINUE HANDLER FOR 1146 begin end; "
      . "REPLACE INTO $new_tbl->{name} ($qcols) VALUES ($new_vals);"
      . "END ";

   # ---------------------------------------------------------------------------------------
   my $upd_index_cols = join(" AND ", map {
          my $new_col = $_;
          my $old_col = $old_col_for{$new_col} || $new_col;
          my $new_qcol = $q->quote($new_col);
          my $old_qcol = $q->quote($old_col);
          "OLD.$old_qcol <=> NEW.$new_qcol"
   } @{$tbl_struct->{keys}->{$del_index}->{cols}} );
   # ---------------------------------------------------------------------------------------

   my $update_trigger
      = "CREATE TRIGGER `${prefix}_upd` AFTER UPDATE ON $orig_tbl->{name} "
      . "FOR EACH ROW "
      . "BEGIN "
      . "DECLARE CONTINUE HANDLER FOR 1146 begin end; "
      . "DELETE IGNORE FROM $new_tbl->{name} WHERE !($upd_index_cols) AND $del_index_cols; "
      . "REPLACE INTO $new_tbl->{name} ($qcols) VALUES ($new_vals); "
      . "END ";

   $triggers_info = [
      {
          suffix => 'del', event => 'DELETE', time => 'AFTER', orig_triggers => [],
          new_trigger_sql => $delete_trigger, new_trigger_name => "${prefix}_del",
      },
      {
          suffix => 'upd', event => 'UPDATE', time => 'AFTER', orig_triggers => [],
          new_trigger_sql => $update_trigger, new_trigger_name => "${prefix}_upd",
      },
      {
          suffix => 'ins', event => 'INSERT', time => 'AFTER', orig_triggers => [],
          new_trigger_sql => $insert_trigger, new_trigger_name => "${prefix}_ins",
      },
      {
          event => 'DELETE', time => 'BEFORE', orig_triggers => [],
      },
      {
          event => 'UPDATE', time => 'BEFORE', orig_triggers => [],
      },
      {
          event => 'INSERT', time => 'BEFORE', orig_triggers => [],
      },
   ];

   $cxn->connect();
   my $dbh = $cxn->dbh();

   my $trigger_sql = "SELECT TRIGGER_SCHEMA, TRIGGER_NAME, DEFINER, ACTION_STATEMENT, SQL_MODE, "
                   . "       CHARACTER_SET_CLIENT, COLLATION_CONNECTION, EVENT_MANIPULATION, ACTION_TIMING "
                   . "  FROM INFORMATION_SCHEMA.TRIGGERS "
                   . " WHERE EVENT_MANIPULATION = ? "
                   . "   AND ACTION_TIMING = ? "
                   . "   AND TRIGGER_SCHEMA = ? "
                   . "   AND EVENT_OBJECT_TABLE = ?";
   foreach my $trigger_info (@$triggers_info) {
       $trigger_info->{orig_triggers} = $dbh->selectall_arrayref( $trigger_sql,
                                                                  { Slice => {} },
                                                                  $trigger_info->{event},
                                                                  $trigger_info->{time},
                                                                  $orig_tbl->{db},
                                                                  $orig_tbl->{tbl}
                                                                ) || [];
   }

   # If --preserve-triggers was specified, try to create the original triggers into the new table.
   # We are doing this to ensure the original triggers will work in the new modified table
   # and we want to know this BEFORE copying all rows from the old table to the new one.
   if ($o->get('preserve-triggers')) {
       foreach my $trigger_info (@$triggers_info) {
           foreach my $orig_trigger (@{$trigger_info->{orig_triggers}}) {
               my $definer = $orig_trigger->{definer} || '';
               $definer =~ s/@/`@`/;
               $definer = "`$definer`" ;

               my @chars = ("a".."z");
               my $tmp_trigger_name;
               $tmp_trigger_name .= $chars[rand @chars] for 1..15;

               my $sql = "CREATE DEFINER=$definer "
                       . "TRIGGER `$new_tbl->{db}`.`$tmp_trigger_name` "
                       . "$orig_trigger->{action_timing} $orig_trigger->{event_manipulation} ON $new_tbl->{tbl}\n"
                       . "FOR EACH ROW\n"
                       . $orig_trigger->{action_statement};
               eval {
                   $dbh->do($sql);
               };
               if ($EVAL_ERROR) {
                   my $msg = "$EVAL_ERROR.\n"
                           . "Check if all fields referenced by the trigger still exists "
                           . "after the operation you are trying to apply";
                   die ($msg);
               }
               $dbh->do("DROP TRIGGER IF EXISTS `$tmp_trigger_name`");
           }
       }
   }

   my @trigger_names;

   foreach my $trigger_info ( @$triggers_info ) {
       next if ! ($trigger_info->{new_trigger_sql});  ###FIXED PT-1919
       if ($o->get('execute') && !$args{dont}) {
           osc_retry(
               Cxn     => $cxn,
               Retry   => $retry,
               tries   => $tries->{create_triggers},
               stats   => $stats,
               code    => sub {
                   PTDEBUG && _d($trigger_info->{new_trigger_sql});
                   $cxn->dbh()->do($trigger_info->{new_trigger_sql});
               },
           );
       }
       # Only save the trigger once it has been created
       # (or faked to be created) so if the 2nd trigger
       # fails to create, we know to only drop the 1st.
       push @trigger_names, $trigger_info->{new_trigger_name};

       if (!$args{'reverse_triggers'}) {
           push @drop_trigger_sqls,
           "DROP TRIGGER IF EXISTS " . $q->quote($orig_tbl->{db}, $trigger_info->{new_trigger_name});
       }
       if ($o->get('print')) {
           print "-----------------------------------------------------------\n";
           print "Skipped trigger creation: \n" if $o->get('dry-run');
           print "Event : $trigger_info->{event} \n";
           print "Name  : $trigger_info->{new_trigger_name} \n";
           print "SQL   : $trigger_info->{new_trigger_sql} \n";
           print "Suffix: $trigger_info->{suffix} \n";
           print "Time  : $trigger_info->{time} \n";
           print "-----------------------------------------------------------\n";
       }
   }

   if ( $o->get('execute') ) {
      print ts("Created triggers OK.\n");
   }
   
   #by silver
   if($o->has('pause-before-data-copy') && defined $o->get('pause-before-data-copy')){
        my $user_input;
        do{
	   print "********************************************************\n";
           print " Pause before data copy. Enter [yes] when you are done.\n";
	   print "********************************************************\n";
	   print ": ";
           chomp ($user_input = <STDIN>);
        }while(!($user_input =~ /yes/i));
   }

   return @trigger_names;
}

sub random_suffix {
    my @chars = ("a".."z");
    my $suffix;
    $suffix .= $chars[rand @chars] for 1..15;
    return "_$suffix";
}

# Create the sql staments for the new trigger
# Required args:
# trigger   : Hash with trigger definition
# db        : Database handle
# new_table : New table name
#
# Optional args:
# orig_table.......: Original table name. Used to LOCK the table.
#                    In case we are creating a new temporary trigger for testing
#                    purposes or if --no-swap-tables is enabled, this param should
#                    be omitted since we are creating a completelly new trigger so,
#                    since in this case we are not going to DROP the old trigger,
#                    there is no need for a LOCK
#
# duplicate_trigger: If set, it will create the trigger on the new table
#                    with a random string as a trigger name suffix.
#                    It will also not drop the original trigger.
#                    This is usefull when creating a temporary trigger for testing
#                    purposes or if --no-swap-tables AND --no-drop-new-table was
#                    specified along with --preserve-triggers. In this case,
#                    since the original table and triggers are not going to be
#                    deleted we need a new random name because trigger names
#                    cannot be duplicated
sub create_trigger_sql {
   my (%args) = @_;
   my @required_args = qw(trigger db new_tbl);
   foreach my $arg ( @required_args ) {
      die "I need a $arg argument" unless $args{$arg};
   }

    my $trigger = $args{trigger};
    my $suffix = $args{duplicate_trigger} ? random_suffix() : '';
    if (length("$trigger->{trigger_name}$suffix") > 64) {
        die "New trigger name $trigger->{trigger_name}$suffix is too long";
    }

    my $definer = $args{trigger}->{definer} | '';
    $definer =~ s/@/`@`/;
    $definer = "`$definer`" ;

    my $sqls = [];
    push @$sqls, "LOCK TABLES `$args{db}`.`$args{new_tbl}` WRITE, `$args{db}`. `$args{orig_tbl}` WRITE;";
    push @$sqls, '/*!50003 SET @saved_sql_mode = @@sql_mode */';
    push @$sqls, '/*!50003 SET @saved_cs_client      = @@character_set_client */ ;';
    push @$sqls, '/*!50003 SET @saved_cs_results     = @@character_set_results */ ;';
    push @$sqls, '/*!50003 SET @saved_col_connection = @@collation_connection */ ;';

    push @$sqls, "/*!50003 SET character_set_client  = $trigger->{character_set_client} */ ;";
    push @$sqls, "/*!50003 SET collation_connection  = $trigger->{collation_connection} */ ;";
    push @$sqls, "SET SESSION sql_mode = '$trigger->{sql_mode}'";

    push @$sqls, "DROP TRIGGER IF EXISTS `$args{db}`.`$trigger->{trigger_name}` " if ! $args{duplicate_trigger};

    push @$sqls, "CREATE DEFINER=$definer "
               . "TRIGGER `$args{db}`.`$trigger->{trigger_name}$suffix` "
               . "$trigger->{action_timing} $trigger->{event_manipulation} ON $args{new_tbl}\n"
               . "FOR EACH ROW\n"
               . $trigger->{action_statement};

    push @$sqls, '/*!50003 SET sql_mode              = @saved_sql_mode */ ;';
    push @$sqls, '/*!50003 SET character_set_client  = @saved_cs_client */ ;';
    push @$sqls, '/*!50003 SET character_set_results = @saved_cs_results */';
    push @$sqls, '/*!50003 SET collation_connection  = @saved_col_connection */ ;';
    push @$sqls, 'UNLOCK TABLES';

   return $sqls;

}

sub drop_triggers {
   my ( %args ) = @_;
   my @required_args = qw(tbl Cxn Quoter OptionParser Retry tries stats);
   foreach my $arg ( @required_args ) {
      die "I need a $arg argument" unless $args{$arg};
   }
   my ($tbl, $cxn, $q, $o, $retry, $tries, $stats) = @args{@required_args};

   # This sub works for --dry-run and --execute, although --dry-run is
   # only interesting with --print so the user can see the drop trigger
   # statements for --execute.
   if ( $o->get('dry-run') ) {
      print "Not dropping triggers because this is a dry run.\n";
   }
   else {
      print ts("Dropping triggers...\n");
   }

   foreach my $sql ( @drop_trigger_sqls ) {
      print $sql, "\n" if $o->get('print');
      if ( $o->get('execute') ) {
         eval {
            osc_retry(
               Cxn     => $cxn,
               Retry   => $retry,
               tries   => $tries->{drop_triggers},
               stats   => $stats,
               code    => sub {
                  PTDEBUG && _d($sql);
                  $cxn->dbh()->do($sql);
               },
            );
         };
         if ( $EVAL_ERROR ) {
            warn ts("Error dropping trigger: $EVAL_ERROR\n");
            push @triggers_not_dropped, $sql;
            $exit_status = 1;
         }
      }
   }

   if ( $o->get('execute') ) {
      if ( !@triggers_not_dropped ) {
         print ts("Dropped triggers OK.\n");
      }
      else {
         warn ts("To try dropping the triggers again, execute:\n"
            . join("\n", @triggers_not_dropped) . "\n");
      }
   }

   return;
}

sub error_event {
   my ($error) = @_;
   return 'undefined_error' unless $error;
   my $event
      = $error =~ m/Lock wait timeout/         ? 'lock_wait_timeout'
      : $error =~ m/Deadlock found/            ? 'deadlock'
      : $error =~ m/execution was interrupted/ ? 'query_killed'
      : $error =~ m/server has gone away/      ? 'lost_connection'
      : $error =~ m/Lost connection/           ? 'connection_killed'
      :                                          'unknown_error';
   return $event;
}

sub osc_retry {
   my (%args) = @_;
   my @required_args = qw(Cxn Retry tries code stats);
   foreach my $arg ( @required_args ) {
      die "I need a $arg argument" unless $args{$arg};
   }

   my $cxn           = $args{Cxn};
   my $retry         = $args{Retry};
   my $tries         = $args{tries};
   my $code          = $args{code};
   my $stats         = $args{stats};
   my $ignore_errors = $args{ignore_errors};

   return $retry->retry(
      tries => $tries->{tries},
      wait  => sub { sleep ($tries->{wait} || 0.25) },
      try   => $code,
      fail => sub {
         my (%args) = @_;
         my $error = $args{error};
         PTDEBUG && _d('Retry fail:', $error);

         if ( $ignore_errors ) {
            if ($error =~ /table.+?already exists/i) {
               PTDEBUG && _d('Aborting retries because of table name conflict. Trying with different name');
            }
            return 0 if grep { $error =~ $_ } @$ignore_errors;
         }

         # The query failed/caused an error.  If the error is one of these,
         # then we can possibly retry.
         if (   $error =~ m/Lock wait timeout exceeded/
             || $error =~ m/Deadlock found/
             || $error =~ m/Query execution was interrupted/
             || $error =~ m/WSREP detected deadlock\/conflict/
         ) {
            # These errors/warnings can be retried, so don't print
            # a warning yet; do that in final_fail.
            $stats->{ error_event($error) }++;
            return 1;  # try again
         }
         elsif (   $error =~ m/MySQL server has gone away/
                || $error =~ m/Lost connection to MySQL server/
         ) {
            # The 1st pattern means that MySQL itself died or was stopped.
            # The 2nd pattern means that our cxn was killed (KILL <id>).
            $stats->{ error_event($error) }++;
            $cxn->connect();  # connect or die trying
            return 1;  # reconnected, try again
         }

         $stats->{retry_fail}++;

         # At this point, either the error/warning cannot be retried,
         # or we failed to reconnect.  Don't retry; call final_fail.
         return 0;
      },
      final_fail => sub {
         my (%args) = @_;
         my $error = $args{error};
         # This die should be caught by the caller.  Copying rows and
         # the tool will stop, which is probably good because by this
         # point the error or warning indicates that something is wrong.
         $stats->{ error_event($error) }++;
         die ts($error);
      }
   );
}

sub exec_nibble {
   my (%args) = @_;
   my @required_args = qw(Cxn tbl stats tries Retry NibbleIterator Quoter);
   foreach my $arg ( @required_args ) {
      die "I need a $arg argument" unless $args{$arg};
   }
   my ($cxn, $tbl, $stats, $tries, $retry, $nibble_iter, $q)
      = @args{@required_args};

   my $sth         = $nibble_iter->statements();
   my $boundary    = $nibble_iter->boundaries();
   my $lb_quoted   = $q->serialize_list(@{$boundary->{lower}});
   my $ub_quoted   = $q->serialize_list(@{$boundary->{upper}});
   my $chunk       = $nibble_iter->nibble_number();
   my $chunk_index = $nibble_iter->nibble_index();


   # Warn once per-table for these error codes if the error message
   # matches the pattern.
   my %warn_code = (
      # Error: 1265 SQLSTATE: 01000 (WARN_DATA_TRUNCATED)
      # Message: Data truncated for column '%s' at row %ld
      1265 => {
         # any pattern
         # use MySQL's message for this warning
      },
   );

   return osc_retry(
      Cxn     => $cxn,
      Retry   => $retry,
      tries   => $tries->{copy_rows},
      stats   => $stats,
      code    => sub {
         # ###################################################################
         # Start timing the query.
         # ###################################################################
         my $t_start = time;

         # Execute the INSERT..SELECT query.
         PTDEBUG && _d($sth->{nibble}->{Statement},
            'lower boundary:', @{$boundary->{lower}},
            'upper boundary:', @{$boundary->{upper}});
         $sth->{nibble}->execute(
            # WHERE
            @{$boundary->{lower}},  # upper boundary values
            @{$boundary->{upper}},  # lower boundary values
         );

         my $t_end = time;
         $stats->{INSERT}++;

         # ###################################################################
         # End timing the query.
         # ###################################################################

         # How many rows were inserted this time.  Used for auto chunk sizing.
         $tbl->{row_cnt} = $sth->{nibble}->rows();

         # Check if query caused any warnings.
         my $sql_warn = 'SHOW WARNINGS';
         PTDEBUG && _d($sql_warn);
         my $warnings = $cxn->dbh->selectall_arrayref($sql_warn, {Slice => {}});
         foreach my $warning ( @$warnings ) {
            my $code    = ($warning->{code} || 0);
            my $message = $warning->{message};
            if ( $ignore_code{$code} ) {
               $stats->{"mysql_warning_$code"}++;
               PTDEBUG && _d('Ignoring warning:', $code, $message);
               next;
            }
            elsif ( $warn_code{$code}
                    && (!$warn_code{$code}->{pattern}
                        || $message =~ m/$warn_code{$code}->{pattern}/) )
            {
               if ( !$stats->{"mysql_warning_$code"}++ ) {  # warn once
                  warn "Copying rows caused a MySQL error $code: "
                     . ($warn_code{$code}->{message}
                        ? $warn_code{$code}->{message}
                        : $message)
                     . "\nNo more warnings about this MySQL error will be "
                     . "reported.  If --statistics was specified, "
                     . "mysql_warning_$code will list the total count of "
                     . "this MySQL error.\n";
               }
            }
            else {
               # This die will propagate to fail which will return 0
               # and propagate it to final_fail which will die with
               # this error message.
               die "Copying rows caused a MySQL error $code:\n"
                  . "    Level: " . ($warning->{level}   || '') . "\n"
                  . "     Code: " . ($warning->{code}    || '') . "\n"
                  . "  Message: " . ($warning->{message} || '') . "\n"
                  . "    Query: " . $sth->{nibble}->{Statement} . "\n";
            }
         }

         # Success: no warnings, no errors.  Return nibble time.
         return $t_end - $t_start;
      },
   );
}

# Sub: explain_statement
#   EXPLAIN a statement.
#
# Required Arguments:
#   * tbl  - Standard tbl hashref
#   * sth  - Sth with EXLAIN <statement>
#   * vals - Values for sth, if any
#
# Returns:
#   Hashref with EXPLAIN plan
sub explain_statement {
   my ( %args ) = @_;
   my @required_args = qw(tbl sth vals);
   foreach my $arg ( @required_args ) {
      die "I need a $arg argument" unless defined $args{$arg};
   }
   my ($tbl, $sth, $vals) = @args{@required_args};

   my $expl;
   eval {
      PTDEBUG && _d($sth->{Statement}, 'params:', @$vals);
      $sth->execute(@$vals);
      $expl = $sth->fetchrow_hashref();
      $sth->finish();
   };
   if ( $EVAL_ERROR ) {
      # This shouldn't happen.
      die "Error executing " . $sth->{Statement} . ": $EVAL_ERROR\n";
   }
   PTDEBUG && _d('EXPLAIN plan:', Dumper($expl));
   return $expl;
}

sub ts {
   my ($msg) = @_;
   my $ts = $ENV{PTTEST_FAKE_TS} ? 'TS' : Transformers::ts(int(time));
   return $msg ? "$ts $msg" : $ts;
}

# find point in trigger we can insert pt-osc code for --preserve-triggers
sub trigger_ins_point {
   my ( %args ) = @_;
   my @required_args = qw(trigger);
   foreach my $arg ( @required_args ) {
      die "I need a $arg argument" unless defined $args{$arg};
   }
   my ($trigger) = @args{@required_args};

   my $ins_point;
   if ($trigger =~ /begin(.*?)end(?!.*end)/igms) {
         $ins_point = $+[0] - 3;
      }
   else { $ins_point = 0;}

   return $ins_point;
}

# sub to add ; if line doesn't end in ;
sub terminate_sql {
   my ( $text ) = @_;
   die "I need a text argument" unless defined $text;
   $text = trim($text);
   if(substr($text, -1) ne ';') { $text .= ';'; }
   return $text;
}

sub trim {
   my ( $text ) = @_;
   die "I need a text argument" unless defined $text;
   $text =~ s/^\s+|\s+$//g;
   return $text;
}

# Catches signals so we can exit gracefully.
sub sig_int {
   my ( $signal ) = @_;
   if ( $dont_interrupt_now ) {
      # we're in the middle of something that shouldn't be interrupted
      PTDEBUG && _d("Received Signal: \"$signal\" in middle of critical operation. Continuing anyway.");
      return;
   }
   $oktorun = 0;  # flag for cleanup tasks
   print STDERR "# Exiting on SIG$signal.\n";
   # This is to restore terminal to "normal". lp #1396870
   if ($term_readkey) {
      ReadMode(0);
   }
   exit 1;
}


sub _d {
   my ($package, undef, $line) = caller 0;
   @_ = map { (my $temp = $_) =~ s/\n/\n# /g; $temp; }
        map { defined $_ ? $_ : 'undef' }
        @_;
   print STDERR "# $package:$line $PID ", join(' ', @_), "\n";
}

# ############################################################################
# Run the program.
# ############################################################################
if ( !caller ) { exit main(@ARGV); }

1; # Because this is a module as well as a script.

# ############################################################################
# Documentation
# ############################################################################
=pod

=head1 NAME

pt-online-schema-change - ALTER tables without locking them.

=head1 SYNOPSIS

Usage: pt-online-schema-change [OPTIONS] DSN

pt-online-schema-change alters a table's structure without blocking reads or
writes.  Specify the database and table in the DSN. Do not use this tool before
reading its documentation and checking your backups carefully.

Add a column to sakila.actor:

  pt-online-schema-change --alter "ADD COLUMN c1 INT" D=sakila,t=actor

Change sakila.actor to InnoDB, effectively performing OPTIMIZE TABLE in a
non-blocking fashion because it is already an InnoDB table:

  pt-online-schema-change --alter "ENGINE=InnoDB" D=sakila,t=actor

=head1 RISKS

Percona Toolkit is mature, proven in the real world, and well tested,
but all database tools can pose a risk to the system and the database
server.  Before using this tool, please:

=over

=item * Read the tool's documentation

=item * Review the tool's known L<"BUGS">

=item * Test the tool on a non-production server

=item * Backup your production server and verify the backups

=back

=head1 DESCRIPTION

pt-online-schema-change emulates the way that MySQL alters tables internally,
but it works on a copy of the table you wish to alter. This means that the
original table is not locked, and clients may continue to read and change data
in it.

pt-online-schema-change works by creating an empty copy of the table to alter,
modifying it as desired, and then copying rows from the original table into the
new table. When the copy is complete, it moves away the original table and
replaces it with the new one.  By default, it also drops the original table.

The data copy process is performed in small chunks of data, which are varied to
attempt to make them execute in a specific amount of time (see
L<"--chunk-time">).  This process is very similar to how other tools, such as
pt-table-checksum, work.  Any modifications to data in the original tables
during the copy will be reflected in the new table, because the tool creates
triggers on the original table to update the corresponding rows in the new
table.  The use of triggers means that the tool will not work if any triggers
are already defined on the table.

When the tool finishes copying data into the new table, it uses an atomic
C<RENAME TABLE> operation to simultaneously rename the original and new tables.
After this is complete, the tool drops the original table.

Foreign keys complicate the tool's operation and introduce additional risk.  The
technique of atomically renaming the original and new tables does not work when
foreign keys refer to the table. The tool must update foreign keys to refer to
the new table after the schema change is complete. The tool supports two methods
for accomplishing this. You can read more about this in the documentation for
L<"--alter-foreign-keys-method">.

Foreign keys also cause some side effects. The final table will have the same
foreign keys and indexes as the original table (unless you specify differently
in your ALTER statement), but the names of the objects may be changed slightly
to avoid object name collisions in MySQL and InnoDB.

For safety, the tool does not modify the table unless you specify the
L<"--execute"> option, which is not enabled by default.  The tool supports a
variety of other measures to prevent unwanted load or other problems, including
automatically detecting replicas, connecting to them, and using the following
safety checks:

=over

=item *

In most cases the tool will refuse to operate unless a PRIMARY KEY or UNIQUE INDEX is
present in the table. See L<"--alter"> for details.


=item *

The tool refuses to operate if it detects replication filters. See
L<"--[no]check-replication-filters"> for details.

=item *

The tool pauses the data copy operation if it observes any replicas that are
delayed in replication. See L<"--max-lag"> for details.

=item *

The tool pauses or aborts its operation if it detects too much load on the
server. See L<"--max-load"> and L<"--critical-load"> for details.

=item *

The tool sets C<innodb_lock_wait_timeout=1> and (for MySQL 5.5 and newer)
C<lock_wait_timeout=60> so that it is more likely to be the victim of any
lock contention, and less likely to disrupt other transactions.  These
values can be changed by specifying L<"--set-vars">.

=item *

The tool refuses to alter the table if foreign key constraints reference it,
unless you specify L<"--alter-foreign-keys-method">.

=item *

The tool cannot alter MyISAM tables on L<"Percona XtraDB Cluster"> nodes.

=back

=head1 Percona XtraDB Cluster

pt-online-schema-change works with Percona XtraDB Cluster (PXC) 5.5.28-23.7
and newer, but there are two limitations: only InnoDB tables can be altered,
and C<wsrep_OSU_method> must be set to C<TOI> (total order isolation).
The tool exits with an error if the host is a cluster node and the table
is MyISAM or is being converted to MyISAM (C<ENGINE=MyISAM>), or if
C<wsrep_OSU_method> is not C<TOI>.  There is no way to disable these checks.

=head1 MySQL 5.7 + Generated columns

The tools ignores MySQL 5.7+ C<GENERATED> columns since the value for those columns
is generated according to the expresion used to compute column values.

=head1 OUTPUT

The tool prints information about its activities to STDOUT so that you can see
what it is doing.  During the data copy phase, it prints L<"--progress">
reports to STDERR.  You can get additional information by specifying
L<"--print">.

If L<"--statistics"> is specified, a report of various internal event counts
is printed at the end, like:

   # Event  Count
   # ====== =====
   # INSERT     1

=head1 OPTIONS

L<"--dry-run"> and L<"--execute"> are mutually exclusive.

This tool accepts additional command-line arguments.  Refer to the
L<"SYNOPSIS"> and usage information for details.

=over

=item --alter

type: string

The schema modification, without the ALTER TABLE keywords. You can perform
multiple modifications to the table by specifying them with commas. Please refer
to the MySQL manual for the syntax of ALTER TABLE.

The following limitations apply which, if attempted, will cause the tool
to fail in unpredictable ways:

=over

=item *

In almost all cases a PRIMARY KEY or UNIQUE INDEX needs to be present in the table.
This is necessary because the tool creates a DELETE trigger to keep the new table
updated while the process is running.

A notable exception is when a PRIMARY KEY or UNIQUE INDEX is being created from
B<existing columns> as part of the ALTER clause; in that case it will use these
column(s) for the DELETE trigger.

=item *

The C<RENAME> clause cannot be used to rename the table.

=item *

Columns cannot be renamed by dropping and re-adding with the new name.
The tool will not copy the original column's data to the new column.

=item *

If you add a column without a default value and make it NOT NULL, the tool
will fail, as it will not try to guess a default value for you; You must
specify the default.

=item *

C<DROP FOREIGN KEY constraint_name> requires specifying C<_constraint_name>
rather than the real C<constraint_name>.  Due to a limitation in MySQL,
pt-online-schema-change adds a leading underscore to foreign key constraint
names when creating the new table.  For example, to drop this constraint:

  CONSTRAINT `fk_foo` FOREIGN KEY (`foo_id`) REFERENCES `bar` (`foo_id`)

You must specify C<--alter "DROP FOREIGN KEY _fk_foo">.

=item *

The tool does not use C<LOCK IN SHARE MODE> with MySQL 5.0 because it can
cause a slave error which breaks replication:

   Query caused different errors on master and slave. Error on master:
   'Deadlock found when trying to get lock; try restarting transaction' (1213),
   Error on slave: 'no error' (0). Default database: 'pt_osc'.
   Query: 'INSERT INTO pt_osc.t (id, c) VALUES ('730', 'new row')'

The error happens when converting a MyISAM table to InnoDB because MyISAM
is non-transactional but InnoDB is transactional.  MySQL 5.1 and newer
handle this case correctly, but testing reproduces the error 5% of the time
with MySQL 5.0.

This is a MySQL bug, similar to L<http://bugs.mysql.com/bug.php?id=45694>,
but there is no fix or workaround in MySQL 5.0.  Without C<LOCK IN SHARE MODE>,
tests pass 100% of the time, so the risk of data loss or breaking replication
should be negligible.

B<Be sure to verify the new table if using MySQL 5.0 and converting
from MyISAM to InnoDB!>

=back

=item --alter-foreign-keys-method

type: string

How to modify foreign keys so they reference the new table.  Foreign keys that
reference the table to be altered must be treated specially to ensure that they
continue to reference the correct table. When the tool renames the original
table to let the new one take its place, the foreign keys "follow" the renamed
table, and must be changed to reference the new table instead.

The tool supports two techniques to achieve this. It automatically finds "child
tables" that reference the table to be altered.

=over

=item auto

Automatically determine which method is best.  The tool uses
C<rebuild_constraints> if possible (see the description of that method for
details), and if not, then it uses C<drop_swap>.

=item rebuild_constraints

This method uses C<ALTER TABLE> to drop and re-add foreign key constraints that
reference the new table.  This is the preferred technique, unless one or more of
the "child" tables is so large that the C<ALTER> would take too long.  The tool
determines that by comparing the number of rows in the child table to the rate
at which the tool is able to copy rows from the old table to the new table. If
the tool estimates that the child table can be altered in less time than the
L<"--chunk-time">, then it will use this technique.  For purposes of estimating
the time required to alter the child table, the tool multiplies the row-copying
rate by L<"--chunk-size-limit">, because MySQL's C<ALTER TABLE> is typically
much faster than the external process of copying rows.

Due to a limitation in MySQL, foreign keys will not have the same names after
the ALTER that they did prior to it. The tool has to rename the foreign key
when it redefines it, which adds a leading underscore to the name. In some
cases, MySQL also automatically renames indexes required for the foreign key.

=item drop_swap

Disable foreign key checks (FOREIGN_KEY_CHECKS=0), then drop the original table
before renaming the new table into its place. This is different from the normal
method of swapping the old and new table, which uses an atomic C<RENAME> that is
undetectable to client applications.

This method is faster and does not block, but it is riskier for two reasons.
First, for a short time between dropping the original table and renaming the
temporary table, the table to be altered simply does not exist, and queries
against it will result in an error.  Secondly, if there is an error and the new
table cannot be renamed into the place of the old one, then it is too late to
abort, because the old table is gone permanently.

This method forces C<--no-swap-tables> and C<--no-drop-old-table>.

=item none

This method is like C<drop_swap> without the "swap".  Any foreign keys that
referenced the original table will now reference a nonexistent table. This will
typically cause foreign key violations that are visible in C<SHOW ENGINE INNODB
STATUS>, similar to the following:

   Trying to add to index `idx_fk_staff_id` tuple:
   DATA TUPLE: 2 fields;
   0: len 1; hex 05; asc  ;;
   1: len 4; hex 80000001; asc     ;;
   But the parent table `sakila`.`staff_old`
   or its .ibd file does not currently exist!

This is because the original table (in this case, sakila.staff) was renamed to
sakila.staff_old and then dropped. This method of handling foreign key
constraints is provided so that the database administrator can disable the
tool's built-in functionality if desired.

=back

=item --[no]analyze-before-swap

default: yes

Execute ANALYZE TABLE on the new table before swapping with the old one.
By default, this happens only when running MySQL 5.6 and newer, and
C<innodb_stats_persistent> is enabled. Specify the option explicitly to enable
or disable it regardless of MySQL version and C<innodb_stats_persistent>.

This circumvents a potentially serious issue related to InnoDB optimizer
statistics. If the table being alerted is busy and the tool completes quickly,
the new table will not have optimizer statistics after being swapped. This can
cause fast, index-using queries to do full table scans until optimizer
statistics are updated (usually after 10 seconds). If the table is large and
the server very busy, this can cause an outage.

=item --ask-pass

Prompt for a password when connecting to MySQL.

=item --channel

type: string

Channel name used when connected to a server using replication channels.
Suppose you have two masters, master_a at port 12345, master_b at port 1236 and
a slave connected to both masters using channels chan_master_a and chan_master_b.
If you want to run pt-table-sync to synchronize the slave against master_a, pt-table-sync
won't be able to determine what's the correct master since SHOW SLAVE STATUS
will return 2 rows. In this case, you can use --channel=chan_master_a to specify
the channel name to use in the SHOW SLAVE STATUS command.

=item --charset

short form: -A; type: string

Default character set.  If the value is utf8, sets Perl's binmode on
STDOUT to utf8, passes the mysql_enable_utf8 option to DBD::mysql, and runs SET
NAMES UTF8 after connecting to MySQL.  Any other value sets binmode on STDOUT
without the utf8 layer, and runs SET NAMES after connecting to MySQL.

=item --[no]check-alter

default: yes

Parses the L<"--alter"> specified and tries to warn of possible unintended
behavior. Currently, it checks for:

=over

=item Column renames

In previous versions of the tool, renaming a column with
C<CHANGE COLUMN name new_name> would lead to that column's data being lost.
The tool now parses the alter statement and tries to catch these cases, so
the renamed columns should have the same data as the originals. However, the
code that does this is not a full-blown SQL parser, so you should first
run the tool with L<"--dry-run"> and L<"--print"> and verify that it detects
the renamed columns correctly.

=item DROP PRIMARY KEY

If L<"--alter"> contain C<DROP PRIMARY KEY> (case- and space-insensitive),
a warning is printed and the tool exits unless L<"--dry-run"> is specified.
Altering the primary key can be dangerous, but the tool can handle it.
The tool's triggers, particularly the DELETE trigger, are most affected by
altering the primary key because the tool prefers to use the primary key
for its triggers.  You should first run the tool with L<"--dry-run"> and
L<"--print"> and verify that the triggers are correct.

=back

=item --[no]check-foreign-keys

default: yes

Check for self-referencing foreign keys. Currently self referencing FKs are
not full supported, so, to prevent errors, this program won't run if the table
has self-referencing foreign keys. Use this parameter to disable self-referencing
FK checks.

=item --check-interval

type: time; default: 1

Sleep time between checks for L<"--max-lag">.

=item --[no]check-plan

default: yes

Check query execution plans for safety. By default, this option causes
the tool to run EXPLAIN before running queries that are meant to access
a small amount of data, but which could access many rows if MySQL chooses a bad
execution plan. These include the queries to determine chunk boundaries and the
chunk queries themselves. If it appears that MySQL will use a bad query
execution plan, the tool will skip the chunk of the table.

The tool uses several heuristics to determine whether an execution plan is bad.
The first is whether EXPLAIN reports that MySQL intends to use the desired index
to access the rows. If MySQL chooses a different index, the tool considers the
query unsafe.

The tool also checks how much of the index MySQL reports that it will use for
the query. The EXPLAIN output shows this in the key_len column. The tool
remembers the largest key_len seen, and skips chunks where MySQL reports that it
will use a smaller prefix of the index. This heuristic can be understood as
skipping chunks that have a worse execution plan than other chunks.

The tool prints a warning the first time a chunk is skipped due to
a bad execution plan in each table. Subsequent chunks are skipped silently,
although you can see the count of skipped chunks in the SKIPPED column in
the tool's output.

This option adds some setup work to each table and chunk. Although the work is
not intrusive for MySQL, it results in more round-trips to the server, which
consumes time. Making chunks too small will cause the overhead to become
relatively larger. It is therefore recommended that you not make chunks too
small, because the tool may take a very long time to complete if you do.

=item --[no]check-replication-filters

default: yes

Abort if any replication filter is set on any server.  The tool looks for
server options that filter replication, such as binlog_ignore_db and
replicate_do_db.  If it finds any such filters, it aborts with an error.

If the replicas are configured with any filtering options, you should be careful
not to modify any databases or tables that exist on the master and not the
replicas, because it could cause replication to fail.  For more information on
replication rules, see L<http://dev.mysql.com/doc/en/replication-rules.html>.

=item --check-slave-lag

type: string

Pause the data copy until this replica's lag is less than L<"--max-lag">.  The
value is a DSN that inherits properties from the the connection options
(L<"--port">, L<"--user">, etc.).  This option overrides the normal behavior of
finding and continually monitoring replication lag on ALL connected replicas.
If you don't want to monitor ALL replicas, but you want more than just one
replica to be monitored, then use the DSN option to the L<"--recursion-method">
option instead of this option.

=item --chunk-index

type: string

Prefer this index for chunking tables.  By default, the tool chooses the most
appropriate index for chunking.  This option lets you specify the index that you
prefer.  If the index doesn't exist, then the tool will fall back to its default
behavior of choosing an index.  The tool adds the index to the SQL statements in
a C<FORCE INDEX> clause.  Be careful when using this option; a poor choice of
index could cause bad performance.

=item --chunk-index-columns

type: int

Use only this many left-most columns of a L<"--chunk-index">.  This works
only for compound indexes, and is useful in cases where a bug in the MySQL
query optimizer (planner) causes it to scan a large range of rows instead
of using the index to locate starting and ending points precisely.  This
problem sometimes occurs on indexes with many columns, such as 4 or more.
If this happens, the tool might print a warning related to the
L<"--[no]check-plan"> option.  Instructing the tool to use only the first
N columns of the index is a workaround for the bug in some cases.

=item --chunk-size

type: size; default: 1000

Number of rows to select for each chunk copied.  Allowable suffixes are
k, M, G.

This option can override the default behavior, which is to adjust chunk size
dynamically to try to make chunks run in exactly L<"--chunk-time"> seconds.
When this option isn't set explicitly, its default value is used as a starting
point, but after that, the tool ignores this option's value.  If you set this
option explicitly, however, then it disables the dynamic adjustment behavior and
tries to make all chunks exactly the specified number of rows.

There is a subtlety: if the chunk index is not unique, then it's possible that
chunks will be larger than desired. For example, if a table is chunked by an
index that contains 10,000 of a given value, there is no way to write a WHERE
clause that matches only 1,000 of the values, and that chunk will be at least
10,000 rows large.  Such a chunk will probably be skipped because of
L<"--chunk-size-limit">.

=item --chunk-size-limit

type: float; default: 4.0

Do not copy chunks this much larger than the desired chunk size.

When a table has no unique indexes, chunk sizes can be inaccurate.  This option
specifies a maximum tolerable limit to the inaccuracy.  The tool uses <EXPLAIN>
to estimate how many rows are in the chunk.  If that estimate exceeds the
desired chunk size times the limit, then the tool skips the chunk.

The minimum value for this option is 1, which means that no chunk can be larger
than L<"--chunk-size">.  You probably don't want to specify 1, because rows
reported by EXPLAIN are estimates, which can be different from the real number
of rows in the chunk.  You can disable oversized chunk checking by specifying a
value of 0.

The tool also uses this option to determine how to handle foreign keys that
reference the table to be altered. See L<"--alter-foreign-keys-method"> for
details.

=item --chunk-time

type: float; default: 0.5

Adjust the chunk size dynamically so each data-copy query takes this long to
execute.  The tool tracks the copy rate (rows per second) and adjusts the chunk
size after each data-copy query, so that the next query takes this amount of
time (in seconds) to execute.  It keeps an exponentially decaying moving average
of queries per second, so that if the server's performance changes due to
changes in server load, the tool adapts quickly.

If this option is set to zero, the chunk size doesn't auto-adjust, so query
times will vary, but query chunk sizes will not. Another way to do the same
thing is to specify a value for L<"--chunk-size"> explicitly, instead of leaving
it at the default.

=item --config

type: Array

Read this comma-separated list of config files; if specified, this must be the
first option on the command line.

=item --critical-load

type: Array; default: Threads_running=50

Examine SHOW GLOBAL STATUS after every chunk, and abort if the load is too high.
The option accepts a comma-separated list of MySQL status variables and
thresholds.  An optional C<=MAX_VALUE> (or C<:MAX_VALUE>) can follow each
variable.  If not given, the tool determines a threshold by examining the
current value at startup and doubling it.

See L<"--max-load"> for further details. These options work similarly, except
that this option will abort the tool's operation instead of pausing it, and the
default value is computed differently if you specify no threshold.  The reason
for this option is as a safety check in case the triggers on the original table
add so much load to the server that it causes downtime.  There is probably no
single value of Threads_running that is wrong for every server, but a default of
50 seems likely to be unacceptably high for most servers, indicating that the
operation should be canceled immediately.

=item --database

short form: -D; type: string

Connect to this database.

=item --default-engine

Remove C<ENGINE> from the new table.

By default the new table is created with the same table options as
the original table, so if the original table uses InnoDB, then the new
table will use InnoDB.  In certain cases involving replication, this may
cause unintended changes on replicas which use a different engine for
the same table.  Specifying this option causes the new table to be
created with the system's default engine.

=item --data-dir

type: string

Create the new table on a different partition using the DATA DIRECTORY feature.
Only available on 5.6+. This parameter is ignored if it is used at the same time
than remove-data-dir.

=item --remove-data-dir

default: no

If the original table was created using the DATA DIRECTORY feature, remove it and create
the new table in MySQL default directory without creating a new isl file.

=item --defaults-file

short form: -F; type: string

Only read mysql options from the given file.  You must give an absolute
pathname.

=item --[no]drop-new-table

default: yes

Drop the new table if copying the original table fails.

Specifying C<--no-drop-new-table> and C<--no-swap-tables> leaves the new,
altered copy of the table without modifying the original table.  See
L<"--new-table-name">.

L<--no-drop-new-table> does not work with
C<alter-foreign-keys-method drop_swap>.

=item --[no]drop-old-table

default: yes

Drop the original table after renaming it. After the original table has been
successfully renamed to let the new table take its place, and if there are no
errors, the tool drops the original table by default. If there are any errors,
the tool leaves the original table in place.

If C<--no-swap-tables> is specified, then there is no old table to drop.

=item --[no]drop-triggers

default: yes

Drop triggers on the old table.  C<--no-drop-triggers> forces
C<--no-drop-old-table>.

=item --dry-run

Create and alter the new table, but do not create triggers, copy data, or
replace the original table.

=item --execute

Indicate that you have read the documentation and want to alter the table.  You
must specify this option to alter the table. If you do not, then the tool will
only perform some safety checks and exit.  This helps ensure that you have read the
documentation and understand how to use this tool.  If you have not read the
documentation, then do not specify this option.

=item --[no]check-unique-key-change

default: yes

Avoid C<pt-online-schema-change> to run if the specified statement for L<"--alter"> is
trying to add an unique index.
Since C<pt-online-schema-change> uses C<INSERT IGNORE> to copy rows to the new table, if
the row being written produces a duplicate key, it will fail silently and data will
be lost.

Example:

    CREATE DATABASE test;
    USE test;
    CREATE TABLE `a` (
      `id` int(11) NOT NULL,
      `unique_id` varchar(32) DEFAULT NULL,
      PRIMARY KEY (`id`)
    ) ENGINE=InnoDB DEFAULT CHARSET=latin1;

    insert into a values (1, "a");
    insert into a values (2, "b");
    insert into a values (3, "");
    insert into a values (4, "");
    insert into a values (5, NULL);
    insert into a values (6, NULL);

Using C<pt-online-schema-change> to add an unique index on the C<unique_id> field, will cause some rows to
be lost due to the use of C<INSERT IGNORE> to copy rows from the source table.
For this reason, C<pt-online-schema-change> will fail if it detects that the L<"--alter"> parameter is trying
to add an unique key and it will show an example query to run to detect if there are
rows that will produce duplicated indexes.

Even if you run the query and there are no rows that will produce duplicated indexes,
take into consideration that after running this query, changes can be made to the table that can produce
duplicate rows and this data will be lost.

=item --force

This options bypasses confirmation in case of using alter-foreign-keys-method = none , which might break foreign key constraints.

=item --help

Show help and exit.

=item --host

short form: -h; type: string

Connect to host.

=item --max-flow-ctl

type: float

Somewhat similar to --max-lag but for PXC clusters.
Check average time cluster spent pausing for Flow Control and make tool pause if
it goes over the percentage indicated in the option.
A value of 0 would make the tool pause when *any* Flow Control activity is
detected.
Default is no Flow Control checking.
This option is available for PXC versions 5.6 or higher.

=item --max-lag

type: time; default: 1s

Pause the data copy until all replicas' lag is less than this value.  After each
data-copy query (each chunk), the tool looks at the replication lag of
all replicas to which it connects, using Seconds_Behind_Master. If any replica
is lagging more than the value of this option, then the tool will sleep
for L<"--check-interval"> seconds, then check all replicas again.  If you
specify L<"--check-slave-lag">, then the tool only examines that server for
lag, not all servers.  If you want to control exactly which servers the tool
monitors, use the DSN value to L<"--recursion-method">.

The tool waits forever for replicas to stop lagging.  If any replica is
stopped, the tool waits forever until the replica is started.  The data copy
continues when all replicas are running and not lagging too much.

The tool prints progress reports while waiting.  If a replica is stopped, it
prints a progress report immediately, then again at every progress report
interval.

=item --max-load

type: Array; default: Threads_running=25

Examine SHOW GLOBAL STATUS after every chunk, and pause if any status variables
are higher than their thresholds.  The option accepts a comma-separated list of
MySQL status variables.  An optional C<=MAX_VALUE> (or C<:MAX_VALUE>) can follow
each variable.  If not given, the tool determines a threshold by examining the
current value and increasing it by 20%.

For example, if you want the tool to pause when Threads_connected gets too high,
you can specify "Threads_connected", and the tool will check the current value
when it starts working and add 20% to that value.  If the current value is 100,
then the tool will pause when Threads_connected exceeds 120, and resume working
when it is below 120 again.  If you want to specify an explicit threshold, such
as 110, you can use either "Threads_connected:110" or "Threads_connected=110".

The purpose of this option is to prevent the tool from adding too much load to
the server. If the data-copy queries are intrusive, or if they cause lock waits,
then other queries on the server will tend to block and queue. This will
typically cause Threads_running to increase, and the tool can detect that by
running SHOW GLOBAL STATUS immediately after each query finishes.  If you
specify a threshold for this variable, then you can instruct the tool to wait
until queries are running normally again.  This will not prevent queueing,
however; it will only give the server a chance to recover from the queueing.  If
you notice queueing, it is best to decrease the chunk time.

=item --preserve-triggers

Preserves old triggers when specified.
As of MySQL 5.7.2, it is possible to define multiple triggers for a given
table that have the same trigger event and action time. This allows us to
add the triggers needed for C<pt-online-schema-change> even if the table
already has its own triggers.
If this option is enabled, C<pt-online-schema-change> will try to copy all the
existing triggers to the new table BEFORE start copying rows from the original
table to ensure the old triggers can be applied after altering the table.

Example.

  CREATE TABLE test.t1 (
       id INT NOT NULL AUTO_INCREMENT,
       f1 INT,
       f2 VARCHAR(32),
       PRIMARY KEY (id)
  );

  CREATE TABLE test.log (
     ts  TIMESTAMP,
     msg VARCHAR(255)
  );

  CREATE TRIGGER test.after_update
   AFTER
     UPDATE ON test.t1
     FOR EACH ROW
       INSERT INTO test.log VALUES (NOW(), CONCAT("updated row row with id ", OLD.id, " old f1:", OLD.f1, " new f1: ", NEW.f1 ));

For this table and triggers combination, it is not possible to use L<--preserve-triggers>
with an L<--alter> like this: C<"DROP COLUMN f1"> since the trigger references the column
being dropped and at would make the trigger to fail.

After testing the triggers will work on the new table, the triggers are
dropped from the new table until all rows have been copied and then they are
re-applied.

L<--preserve-triggers> cannot be used with these other parameters, L<--no-drop-triggers>,
L<--no-drop-old-table> and L<--no-swap-tables> since L<--preserve-triggers> implies that
the old triggers should be deleted and recreated in the new table.
Since it is not possible to have more than one trigger with the same name, old triggers
must be deleted in order to be able to recreate them into the new table.

Using C<--preserve-triggers> with C<--no-swap-tables> will cause triggers to remain
defined for the original table.
Please read the documentation for L<--swap-tables>

If both C<--no-swap-tables> and C<--no-drop-new-table> is set, the trigger will remain
on the original table and will be duplicated on the new table
(the trigger will have a random suffix as no trigger names are unique).

=item --new-table-name

type: string; default: %T_new

New table name before it is swapped.  C<%T> is replaced with the original
table name.  When the default is used, the tool prefixes the name with up
to 10 C<_> (underscore) to find a unique table name.  If a table name is
specified, the tool does not prefix it with C<_>, so the table must not
exist.

=item --null-to-not-null

Allows MODIFYing a column that allows NULL values to one that doesn't allow
them. The rows which contain NULL values will be converted to the defined
default value. If no explicit DEFAULT value is given MySQL will assign a default
value based on datatype, e.g. 0 for number datatypes, '' for string datatypes.

=item --only-same-schema-fks

Check foreigns keys only on tables on the same schema than the original table.
This option is dangerous since if you have FKs refenrencing tables in other
schemas, they won't be detected.


=item --password

short form: -p; type: string

Password to use when connecting.
If password contains commas they must be escaped with a backslash: "exam\,ple"

=item --pause-file

type: string

Execution will be paused while the file specified by this param exists.

=item --pid

type: string

Create the given PID file.  The tool won't start if the PID file already
exists and the PID it contains is different than the current PID.  However,
if the PID file exists and the PID it contains is no longer running, the
tool will overwrite the PID file with the current PID.  The PID file is
removed automatically when the tool exits.

=item --plugin

type: string

Perl module file that defines a C<pt_online_schema_change_plugin> class.
A plugin allows you to write a Perl module that can hook into many parts
of pt-online-schema-change.  This requires a good knowledge of Perl and
Percona Toolkit conventions, which are beyond this scope of this
documentation.  Please contact Percona if you have questions or need help.

See L<"PLUGIN"> for more information.

=item --port

short form: -P; type: int

Port number to use for connection.

=item --print

Print SQL statements to STDOUT.  Specifying this option allows you to see most
of the statements that the tool executes. You can use this option with
L<"--dry-run">, for example.

=item --progress

type: array; default: time,30

Print progress reports to STDERR while copying rows.  The value is a
comma-separated list with two parts.  The first part can be percentage, time, or
iterations; the second part specifies how often an update should be printed, in
percentage, seconds, or number of iterations.

=item --quiet

short form: -q

Do not print messages to STDOUT (disables L<"--progress">).
Errors and warnings are still printed to STDERR.

=item --pause-before-data-copy

Pause before data copy into _[table]_new

=item --recurse

type: int

Number of levels to recurse in the hierarchy when discovering replicas.
Default is infinite.  See also L<"--recursion-method">.

=item --recursion-method

type: array; default: processlist,hosts

Preferred recursion method for discovering replicas.  Possible methods are:

  METHOD       USES
  ===========  ==================
  processlist  SHOW PROCESSLIST
  hosts        SHOW SLAVE HOSTS
  dsn=DSN      DSNs from a table
  none         Do not find slaves

The processlist method is the default, because SHOW SLAVE HOSTS is not
reliable.  However, the hosts method can work better if the server uses a
non-standard port (not 3306).  The tool usually does the right thing and
finds all replicas, but you may give a preferred method and it will be used
first.

The hosts method requires replicas to be configured with report_host,
report_port, etc.

The dsn method is special: it specifies a table from which other DSN strings
are read.  The specified DSN must specify a D and t, or a database-qualified
t.  The DSN table should have the following structure:

  CREATE TABLE `dsns` (
    `id` int(11) NOT NULL AUTO_INCREMENT,
    `parent_id` int(11) DEFAULT NULL,
    `dsn` varchar(255) NOT NULL,
    PRIMARY KEY (`id`)
  );

To make the tool monitor only the hosts 10.10.1.16 and 10.10.1.17 for
replication lag, insert the values C<h=10.10.1.16> and C<h=10.10.1.17> into the
table. Currently, the DSNs are ordered by id, but id and parent_id are otherwise
ignored.

You can change the list of hosts while OSC is executing:
if you change the contents of the DSN table, OSC will pick it up very soon.

=item --reverse-triggers
Copy the triggers added during the copy in reverse order. Commands in the new table will be
reflected in the old table. You can use this as a safety feature, so that the old
table continues to receive updates. This option requires C<--no-drop-old-table>.

Warning! This option creates reverse triggers on the new table before it starts copying.
After new table is renamed to its original name triggers will continue working. But because the
name change metadata version in the table cache will also change you may start receiving
"Prepared statement needs to be re-prepared" errors. The workaround for this is to re-prepare statements.
If you do not use server-side prepared statements your application should not be affected.

=item --skip-check-slave-lag

type: DSN; repeatable: yes

DSN to skip when checking slave lag. It can be used multiple times.
Example: --skip-check-slave-lag h=127.0.0.1,P=12345 --skip-check-slave-lag h=127.0.0.1,P=12346
Plase take into consideration that even when for the MySQL driver h=127.1 is equal to h=127.0.0.1,
for this parameter you need to specify the full IP address.

=item --slave-user

type: string

Sets the user to be used to connect to the slaves.
This parameter allows you to have a different user with less privileges on the
slaves but that user must exist on all slaves.

=item --slave-password

type: string

Sets the password to be used to connect to the slaves.
It can be used with --slave-user and the password for the user must be the same
on all slaves.

=item --set-vars

type: Array

Set the MySQL variables in this comma-separated list of C<variable=value> pairs.

By default, the tool sets:

=for comment ignore-pt-internal-value
MAGIC_set_vars

   wait_timeout=10000
   innodb_lock_wait_timeout=1
   lock_wait_timeout=60

Variables specified on the command line override these defaults.  For
example, specifying C<--set-vars wait_timeout=500> overrides the default
value of C<10000>.

The tool prints a warning and continues if a variable cannot be set.

Note that setting the C<sql_mode> variable requires some tricky escapes
to be able to parse the quotes and commas.

Example:

   --set-vars sql_mode=\'STRICT_ALL_TABLES\\,ALLOW_INVALID_DATES\'

Note the single backslash for the quotes and double backslash for the comma.

=item --sleep

type: float; default: 0

How long to sleep (in seconds) after copying each chunk. This option is useful
when throttling by L<"--max-lag"> and L<"--max-load"> are not possible.
A small, sub-second value should be used, like 0.1, else the tool could take
a very long time to copy large tables.

=item --socket

short form: -S; type: string

Socket file to use for connection.

=item --statistics

Print statistics about internal counters.  This is useful to see how
many warnings were suppressed compared to the number of INSERT.

=item --[no]swap-tables

default: yes

Swap the original table and the new, altered table.  This step completes the
online schema change process by making the table with the new schema take the
place of the original table.  The original table becomes the "old table," and
the tool drops it unless you disable L<"--[no]drop-old-table">.

Using C<--no-swap-tables> will run the whole process, it will create the new
table, it will copy all rows but at the end it will drop the new table. It is
intended to run a more realistic L<--dry-run>.

=item --tries

type: array

How many times to try critical operations.  If certain operations fail due
to non-fatal, recoverable errors, the tool waits and tries the operation
again.  These are the operations that are retried, with their default number
of tries and wait time between tries (in seconds):

=for comment ignore-pt-internal-value
MAGIC_tries

   OPERATION            TRIES   WAIT
   ===================  =====   ====
   create_triggers         10      1
   drop_triggers           10      1
   copy_rows               10   0.25
   swap_tables             10      1
   update_foreign_keys     10      1
   analyze_table           10      1

To change the defaults, specify the new values like:

   --tries create_triggers:5:0.5,drop_triggers:5:0.5

That makes the tool try C<create_triggers> and C<drop_triggers> 5 times
with a 0.5 second wait between tries.  So the format is:

   operation:tries:wait[,operation:tries:wait]

All three values must be specified.

Note that most operations are affected only in MySQL 5.5 and newer by
C<lock_wait_timeout> (see L<"--set-vars">) because of metadata locks.
The C<copy_rows> operation is affected in any version of MySQL by
C<innodb_lock_wait_timeout>.

For creating and dropping triggers, the number of tries applies to each
C<CREATE TRIGGER> and C<DROP TRIGGER> statement for each trigger.
For copying rows, the number of tries applies to each chunk, not the
entire table.  For swapping tables, the number of tries usually applies
once because there is usually only one C<RENAME TABLE> statement.
For rebuilding foreign key constraints, the number of tries applies to
each statement (C<ALTER> statements for the C<rebuild_constraints>
L<"--alter-foreign-keys-method">; other statements for the C<drop_swap>
method).

The tool retries each operation if these errors occur:

   Lock wait timeout (innodb_lock_wait_timeout and lock_wait_timeout)
   Deadlock found
   Query is killed (KILL QUERY <thread_id>)
   Connection is killed (KILL CONNECTION <thread_id>)
   Lost connection to MySQL

In the case of lost and killed connections, the tool will automatically
reconnect.

Failures and retries are recorded in the L<"--statistics">.

=item --user

short form: -u; type: string

User for login if not current user.

=item --version

Show version and exit.

=item --[no]version-check

default: yes

Check for the latest version of Percona Toolkit, MySQL, and other programs.

This is a standard "check for updates automatically" feature, with two
additional features.  First, the tool checks its own version and also the
versions of the following software: operating system, Percona Monitoring and
Management (PMM), MySQL, Perl, MySQL driver for Perl (DBD::mysql), and
Percona Toolkit. Second, it checks for and warns about versions with known
problems. For example, MySQL 5.5.25 had a critical bug and was re-released
as 5.5.25a.

A secure connection to Percona’s Version Check database server is done to
perform these checks. Each request is logged by the server, including software
version numbers and unique ID of the checked system. The ID is generated by the
Percona Toolkit installation script or when the Version Check database call is
done for the first time.

Any updates or known problems are printed to STDOUT before the tool's normal
output.  This feature should never interfere with the normal operation of the
tool.

For more information, visit L<https://www.percona.com/doc/percona-toolkit/LATEST/version-check.html>.

=back

=head1 PLUGIN

The file specified by L<"--plugin"> must define a class (i.e. a package)
called C<pt_online_schema_change_plugin> with a C<new()> subroutine.
The tool will create an instance of this class and call any hooks that
it defines.  No hooks are required, but a plugin isn't very useful without
them.

These hooks, in this order, are called if defined:

   init
   before_create_new_table
   after_create_new_table
   before_alter_new_table
   after_alter_new_table
   before_create_triggers
   after_create_triggers
   before_copy_rows
   after_copy_rows
   before_swap_tables
   after_swap_tables
   before_update_foreign_keys
   after_update_foreign_keys
   before_drop_old_table
   after_drop_old_table
   before_drop_triggers
   before_exit
   get_slave_lag

Each hook is passed different arguments.  To see which arguments are passed
to a hook, search for the hook's name in the tool's source code, like:

   # --plugin hook
   if ( $plugin && $plugin->can('init') ) {
      $plugin->init(
         orig_tbl       => $orig_tbl,
         child_tables   => $child_tables,
         renamed_cols   => $renamed_cols,
         slaves         => $slaves,
         slave_lag_cxns => $slave_lag_cxns,
      );
   }

The comment C<# --plugin hook> precedes every hook call.

Here's a plugin file template for all hooks:

   package pt_online_schema_change_plugin;

   use strict;

   sub new {
      my ($class, %args) = @_;
      my $self = { %args };
      return bless $self, $class;
   }

   sub init {
      my ($self, %args) = @_;
      print "PLUGIN init\n";
   }

   sub before_create_new_table {
      my ($self, %args) = @_;
      print "PLUGIN before_create_new_table\n";
   }

   sub after_create_new_table {
      my ($self, %args) = @_;
      print "PLUGIN after_create_new_table\n";
   }

   sub before_alter_new_table {
      my ($self, %args) = @_;
      print "PLUGIN before_alter_new_table\n";
   }

   sub after_alter_new_table {
      my ($self, %args) = @_;
      print "PLUGIN after_alter_new_table\n";
   }

   sub before_create_triggers {
      my ($self, %args) = @_;
      print "PLUGIN before_create_triggers\n";
   }

  sub after_create_triggers {
      my ($self, %args) = @_;
      print "PLUGIN after_create_triggers\n";
   }

   sub before_copy_rows {
      my ($self, %args) = @_;
      print "PLUGIN before_copy_rows\n";
   }

   sub after_copy_rows {
      my ($self, %args) = @_;
      print "PLUGIN after_copy_rows\n";
   }

   sub before_swap_tables {
      my ($self, %args) = @_;
      print "PLUGIN before_swap_tables\n";
   }

   sub after_swap_tables {
      my ($self, %args) = @_;
      print "PLUGIN after_swap_tables\n";
   }

   sub before_update_foreign_keys {
      my ($self, %args) = @_;
      print "PLUGIN before_update_foreign_keys\n";
   }

   sub after_update_foreign_keys {
      my ($self, %args) = @_;
      print "PLUGIN after_update_foreign_keys\n";
   }

   sub before_drop_old_table {
      my ($self, %args) = @_;
      print "PLUGIN before_drop_old_table\n";
   }

   sub after_drop_old_table {
      my ($self, %args) = @_;
      print "PLUGIN after_drop_old_table\n";
   }

   sub before_drop_triggers {
      my ($self, %args) = @_;
      print "PLUGIN before_drop_triggers\n";
   }

   sub before_exit {
      my ($self, %args) = @_;
      print "PLUGIN before_exit\n";
   }

   sub get_slave_lag {
      my ($self, %args) = @_;
      print "PLUGIN get_slave_lag\n";

      return sub { return 0; };
   }

   1;

Notice that C<get_slave_lag> must return a function reference;
ideally one that returns actual slave lag, not simply zero like in the example.

Here's an example that actually does something:

   package pt_online_schema_change_plugin;

   use strict;

   sub new {
      my ($class, %args) = @_;
      my $self = { %args };
      return bless $self, $class;
   }

   sub after_create_new_table {
      my ($self, %args) = @_;
      my $new_tbl = $args{new_tbl};
      my $dbh     = $self->{cxn}->dbh;
      my $row = $dbh->selectrow_arrayref("SHOW CREATE TABLE $new_tbl->{name}");
      warn "after_create_new_table: $row->[1]\n\n";
   }

   sub after_alter_new_table {
      my ($self, %args) = @_;
      my $new_tbl = $args{new_tbl};
      my $dbh     = $self->{cxn}->dbh;
      my $row = $dbh->selectrow_arrayref("SHOW CREATE TABLE $new_tbl->{name}");
      warn "after_alter_new_table: $row->[1]\n\n";
   }

   1;

You could use this with L<"--dry-run"> to check how the table will look before and after.

Please contact Percona if you have questions or need help.

=head1 DSN OPTIONS

These DSN options are used to create a DSN.  Each option is given like
C<option=value>.  The options are case-sensitive, so P and p are not the
same option.  There cannot be whitespace before or after the C<=> and
if the value contains whitespace it must be quoted.  DSN options are
comma-separated.  See the L<percona-toolkit> manpage for full details.

=over

=item * A

dsn: charset; copy: yes

Default character set.

=item * D

dsn: database; copy: no

Database for the old and new table.

=item * F

dsn: mysql_read_default_file; copy: yes

Only read default options from the given file

=item * h

dsn: host; copy: yes

Connect to host.

=item * p

dsn: password; copy: yes

Password to use when connecting.
If password contains commas they must be escaped with a backslash: "exam\,ple"

=item * P

dsn: port; copy: no

Port number to use for connection.

=item * S

dsn: mysql_socket; copy: yes

Socket file to use for connection.

=item * t

dsn: table; copy: no

Table to alter.

=item * u

dsn: user; copy: yes

User for login if not current user.

=back

=head1 ENVIRONMENT

The environment variable C<PTDEBUG> enables verbose debugging output to STDERR.
To enable debugging and capture all output to a file, run the tool like:

   PTDEBUG=1 pt-online-schema-change ... > FILE 2>&1

Be careful: debugging output is voluminous and can generate several megabytes
of output.

=head1 ATTENTION

Using <PTDEBUG> might expose passwords. When debug is enabled, all command line 
parameters are shown in the output.

=head1 EXIT STATUS

   INVALID_PARAMETERS              = 1
   UNSUPORTED_MYSQL_VERSION        = 2
   NO_MINIMUM_REQUIREMENTS         = 3
   NO_PRIMARY_OR_UNIQUE_KEY        = 4
   INVALID_PLUGIN_FILE             = 5
   INVALID_ALTER_FK_METHOD         = 6
   INVALID_KEY_SIZE                = 7
   CANNOT_DETERMINE_KEY_SIZE       = 9
   NOT_SAFE_TO_ASCEND              = 9
   ERROR_CREATING_NEW_TABLE        = 10
   ERROR_ALTERING_TABLE            = 11
   ERROR_CREATING_TRIGGERS         = 12
   ERROR_RESTORING_TRIGGERS        = 13
   ERROR_SWAPPING_TABLES           = 14
   ERROR_UPDATING_FKS              = 15
   ERROR_DROPPING_OLD_TABLE        = 16
   UNSUPORTED_OPERATION            = 17
   MYSQL_CONNECTION_ERROR          = 18
   LOST_MYSQL_CONNECTION           = 19
   ERROR_CREATING_REVERSE_TRIGGERS = 20

=head1 SYSTEM REQUIREMENTS

You need Perl, DBI, DBD::mysql, and some core packages that ought to be
installed in any reasonably new version of Perl.

This tool works only on MySQL 5.0.2 and newer versions, because earlier versions
do not support triggers. Also a number of permissions should be set on MySQL
to make pt-online-schema-change operate as expected. PROCESS, SUPER, REPLICATION SLAVE
global privileges, as well as SELECT, INSERT, UPDATE, DELETE, CREATE, DROP, ALTER,
and TRIGGER table privileges should be granted on server. Slave needs only
REPLICATION SLAVE and REPLICATION CLIENT privileges.

=head1 BUGS

For a list of known bugs, see L<http://www.percona.com/bugs/pt-online-schema-change>.

Please report bugs at L<https://bugs.launchpad.net/percona-toolkit>.
Include the following information in your bug report:

=over

=item * Complete command-line used to run the tool

=item * Tool L<"--version">

=item * MySQL version of all servers involved

=item * Output from the tool including STDERR

=item * Input files (log/dump/config files, etc.)

=back

If possible, include debugging output by running the tool with C<PTDEBUG>;
see L<"ENVIRONMENT">.

=head1 DOWNLOADING

Visit L<http://www.percona.com/software/percona-toolkit/> to download the
latest release of Percona Toolkit.  Or, get the latest release from the
command line:

   wget percona.com/get/percona-toolkit.tar.gz

   wget percona.com/get/percona-toolkit.rpm

   wget percona.com/get/percona-toolkit.deb

You can also get individual tools from the latest release:

   wget percona.com/get/TOOL

Replace C<TOOL> with the name of any tool.

=head1 AUTHORS

Daniel Nichter and Baron Schwartz

=head1 ACKNOWLEDGMENTS

The "online schema change" concept was first implemented by Shlomi Noach
in his tool C<oak-online-alter-table>, part of
L<http://code.google.com/p/openarkkit/>.  Engineers at Facebook then built
another version called C<OnlineSchemaChange.php> as explained by their blog
post: L<http://tinyurl.com/32zeb86>. This tool is a hybrid of both approaches,
with additional features and functionality not present in either.

=head1 ABOUT PERCONA TOOLKIT

This tool is part of Percona Toolkit, a collection of advanced command-line
tools for MySQL developed by Percona.  Percona Toolkit was forked from two
projects in June, 2011: Maatkit and Aspersa.  Those projects were created by
Baron Schwartz and primarily developed by him and Daniel Nichter.  Visit
L<http://www.percona.com/software/> to learn about other free, open-source
software from Percona.

=head1 COPYRIGHT, LICENSE, AND WARRANTY

This program is copyright 2011-2021 Percona LLC and/or its affiliates.

THIS PROGRAM IS PROVIDED "AS IS" AND WITHOUT ANY EXPRESS OR IMPLIED
WARRANTIES, INCLUDING, WITHOUT LIMITATION, THE IMPLIED WARRANTIES OF
MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE.

This program is free software; you can redistribute it and/or modify it under
the terms of the GNU General Public License as published by the Free Software
Foundation, version 2; OR the Perl Artistic License.  On UNIX and similar
systems, you can issue `man perlgpl' or `man perlartistic' to read these
licenses.

You should have received a copy of the GNU General Public License along with
this program; if not, write to the Free Software Foundation, Inc., 59 Temple
Place, Suite 330, Boston, MA  02111-1307  USA.

=head1 VERSION

pt-online-schema-change 3.5.0

=cut
