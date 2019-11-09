package Mock::GoogleDrive;
use Mojo::Base -base;
sub children {
	warn 'children '. join(',',@_);
	return 'children LEGG INN NOE LURT HER'
}
sub search{
	warn 'search '. join(',',@_);
	return []; #'search LEGG INN NOE LURT HER'
}
sub path_resolve {
	warn 'path_resolve '. join(',',@_);
	return 'path_resolve LEGG INN NOE LURT HER'
}

sub file_metadata {
	warn 'file_metadata '. join(',',@_);
	return 'file_metadata LEGG INN NOE LURT HER'
}

1;