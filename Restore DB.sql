--This script restores a database with no secondary files (no .ndf) from backup
--if database doesn't exist already it creates it in the same .mdf and .ldf folders as @rcacode
--3 variables on lines 7, 8, 10
USE master;
GO

SET NOCOUNT ON;

DECLARE @dbtorestore AS sysname = N'RCA_Tier2_NewHire_Framework';	--database to be restored
DECLARE @sampledb AS sysname = N'Dev_22C_Code';	--this is used only in case database doesn't already exist, files would be put in the same folder as this database

DECLARE @backupfullpath AS NVARCHAR(260) = N'D:\Sam\Framework.bak';	--full path of .bak file to be restored

DECLARE @sa NVARCHAR(128);
SELECT @sa = [name] FROM sys.server_principals WHERE [sid] = 0x01;

DECLARE @codedbexist BIT = 'false';
DECLARE @sql NVARCHAR(4000);

DECLARE @rowsfilepath AS NVARCHAR(260),
		@logfilepath AS NVARCHAR(260);

DECLARE @logicalrowsname AS sysname,
		@logicallogname AS sysname;


DECLARE @temptable AS TABLE (
							LogicalName NVARCHAR(128), PhysicalName NVARCHAR(260), [Type] CHAR(1),
							FileGroupName NVARCHAR(128), Size NUMERIC(20,0), MaxSize NUMERIC(20,0),
							FileID BIGINT, CreateLSN NUMERIC(25,0), DropLSN NUMERIC(25,0),
							UniqueID UNIQUEIDENTIFIER, ReadOnlyLSN NUMERIC(25,0), ReadWriteLSN NUMERIC(25,0),
							BackupSizeInBytes BIGINT, SourceBlockSize INT, FileGroupID INT,
							LogGroupGUID UNIQUEIDENTIFIER, DifferentialBaseLSN NUMERIC(25,0),
							DifferentialBaseGUID UNIQUEIDENTIFIER, IsReadOnly BIT, IsPresent BIT,
							TDEThumbprint VARBINARY(320)
							);
INSERT INTO @temptable
EXEC(
		'restore filelistonly
		from disk = ''' + @backupfullpath + ''' with file = 1'
		);
		      
SELECT @logicalrowsname = LogicalName
FROM @temptable
WHERE [Type] = 'D';

SELECT @logicallogname = LogicalName
FROM @temptable
WHERE [Type] = 'L';
	
IF EXISTS(SELECT * FROM sys.databases WHERE name = @dbtorestore)
BEGIN
	SET @codedbexist = 'true';
	SELECT @rowsfilepath = SUBSTRING(physical_name, 0, LEN(physical_name) - 3)
	FROM sys.master_files
	WHERE DB_NAME(database_id) = @dbtorestore
		AND type_desc = N'ROWS';

	SELECT @logfilepath = SUBSTRING(physical_name, 0, LEN(physical_name) - 3)
	FROM sys.master_files
	WHERE DB_NAME(database_id) = @dbtorestore
		AND type_desc = N'LOG';
END
ELSE
BEGIN
	SET @codedbexist = 'false';
	SELECT @rowsfilepath = REVERSE(SUBSTRING(REVERSE(physical_name),CHARINDEX('\',REVERSE(physical_name),1),LEN(physical_name))) + @dbtorestore
	FROM sys.master_files
	WHERE DB_NAME(database_id) = @sampledb
		AND type_desc = N'ROWS';

	SELECT @logfilepath = REVERSE(SUBSTRING(REVERSE(physical_name),CHARINDEX('\',REVERSE(physical_name),1),LEN(physical_name))) + @dbtorestore
	FROM sys.master_files
	WHERE DB_NAME(database_id) = @sampledb
		AND type_desc = N'LOG';
END


DECLARE @logresult INT = 1;
DECLARE @mdfresult INT = 1;
DECLARE @logfilefullpath VARCHAR(260) = @logfilepath + '.ldf';
DECLARE @mdffilefullpath VARCHAR(260) = @rowsfilepath + '.mdf';
DECLARE @append TINYINT = 1;

EXEC master.dbo.xp_fileexist @logfilefullpath, @logresult OUTPUT;
EXEC master.dbo.xp_fileexist @mdffilefullpath, @mdfresult OUTPUT;

WHILE (@codedbexist = 'false' AND @logresult + @mdfresult >= 1 AND @append < 20)
BEGIN
	SELECT @logfilefullpath = @logfilepath + CAST(@append AS VARCHAR(2)) + '.ldf';
	SELECT @mdffilefullpath = @rowsfilepath + CAST(@append AS VARCHAR(2)) + '.mdf';
	
	EXEC master.dbo.xp_fileexist @logfilefullpath, @logresult OUTPUT;
	EXEC master.dbo.xp_fileexist @mdffilefullpath, @mdfresult OUTPUT;

	SET @append += 1;
END


SET @sql = N'
	ALTER DATABASE ' + @dbtorestore + N'
		SET SINGLE_USER WITH ROLLBACK AFTER 60;
	';

IF EXISTS(SELECT * FROM sys.databases WHERE name = @dbtorestore)
BEGIN
	EXEC sp_executesql @statement = @sql;
END


SET @sql = N'
	RESTORE DATABASE ' + @dbtorestore + N'
	FROM  DISK = ''' + @backupfullpath + N'''
	WITH  FILE = 1,
		MOVE ''' + @logicalrowsname + N''' TO ''' + @mdffilefullpath + N''',
		MOVE ''' + @logicallogname + N''' TO ''' + @logfilefullpath + N''', 
		NOUNLOAD,  REPLACE,  STATS = 10;
	';

EXEC sp_executesql @statement = @sql;
	

SET @sql = N'
	ALTER DATABASE ' + @dbtorestore + N'
		SET MULTI_USER;
	';

EXEC sp_executesql @statament = @sql;


--set compatibility level to current SQL version
DECLARE @productversion NVARCHAR(100);
DECLARE @compatibilitylevel NVARCHAR(3);
SELECT @productversion = CONVERT(NVARCHAR(100),SERVERPROPERTY('productversion'));

SELECT @compatibilitylevel =
	CAST(CAST(SUBSTRING(@productversion,1,CHARINDEX('.',@productversion,1) - 1) AS INT) * 10 AS NVARCHAR(3));

IF EXISTS(SELECT * FROM sys.databases WHERE name = @dbtorestore)
BEGIN
	SET @sql = N'
		ALTER DATABASE ' + @dbtorestore + N' SET COMPATIBILITY_LEVEL = ' + @compatibilitylevel + N';
		ALTER DATABASE ' + @dbtorestore + N' SET RECOVERY SIMPLE WITH NO_WAIT;'

	EXEC sp_executesql @statement = @sql;
END;


SELECT @sql = N'
USE [' + @dbtorestore + N']

EXEC dbo.sp_changedbowner @loginame = ' + @sa + N', @map = false';

EXEC sp_executesql @statement = @sql;

PRINT @dbtorestore + N' owner set to SA';

