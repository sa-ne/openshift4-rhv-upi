<?php
    $dns = gethostbyaddr($_SERVER['REMOTE_ADDR']);

    if(stristr($dns, "bootstrap"))
        $file = "bootstrap.ign";
    else if(stristr($dns, "master"))
        $file = "master.ign";
	else if (stristr($dns, "infra"))
        $file = "infra.ign";
	else if (stristr($dns, "ocs"))
        $file = "ocs.ign";
	else
        $file = "worker.ign";

    if(file_exists("/var/www/html/$file"))
    {
        header("Content-Description: File Transfer");
        header("Content-Disposition: attachment; filename=$file");
        header("Content-Type: application/octet-stream");
        header("Expires: 0");
        header("Cache-Control: must-revalidate");
        header("Pragma: public");
        header("Content-Length: " . filesize("/var/www/html/$file"));

        flush();
        readfile($file);
    }
?>
