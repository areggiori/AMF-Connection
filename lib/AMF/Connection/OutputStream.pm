package AMF::Connection::OutputStream;

use strict;
use Carp;

use Storable::AMF0;
use Storable::AMF3;

sub new {
	my $proto = shift;
	my $class = ref($proto) || $proto;
	
	my $self = {
		'stream' => ''
		};

	return bless($self, $class);
	};

sub writeBuffer {
	my ($class, $str) = @_;

	$class->{'stream'}.=$str;
	};

sub writeByte {
	my ($class, $byte) = @_;

	$class->{'stream'}.=pack("c",$byte);
	};

sub writeInt {
	my ($class, $int) = @_;

	$class->{'stream'}.=pack("n",$int);
	};

sub writeDouble {
	my ($class, $double) = @_;

        my $bin = pack("d",$double);
        my @testEndian = unpack("C*",pack("S*",256));
        my $bigEndian = !$testEndian[1]==1;
        $bin = reverse($bin)
                if ($bigEndian);

	$class->{'stream'}.=$bin;
	};

sub writeLong {
	my ($class, $long) = @_;

	$class->{'stream'}.=pack("N",$long);
	};

sub getStreamData {
	my ($class) = @_;
	
	return $class->{'stream'};
	};

# wrtie an AMF entity
sub writeAMFData {
        my ($class,$encoding,$data) = @_;

	local $@ = undef;

	my $bytes;
        if($encoding == 3 ) {
		$bytes = Storable::AMF3::freeze($data);
		$class->writeByte(0x11);
        } else {
		$bytes = Storable::AMF0::freeze($data);
                };

	croak "Can not write AMF".$encoding." data starting from position ".$class->{'cursor'}." of input - reason: ".$@ ."\n"
		if($@);

	$class->writeBuffer($bytes);
        };

1;
__END__

=head1 NAME

AMF::Connection::OutputStream - A simple pure perl implementation of an output binary stream

=head1 SYNOPSIS

  # ...

  my $stream = new AMF::Connection::OutputStream;
  $stream->writeInt(1);
  $stream->writeLong(1);

  # ..


=head1 DESCRIPTION

The AMF::Connection::OutputStream class is a simple pure perl implementation of an output binary stream.

=head1 SEE ALSO

Data::AMF::IO, AMF::Perl::IO::OutputStream

=head1 AUTHOR

Alberto Attilio Reggiori, <areggiori at cpan dot org>

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2010 by Alberto Attilio Reggiori

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.10.0 or,
at your option, any later version of Perl 5 you may have available.

=cut
