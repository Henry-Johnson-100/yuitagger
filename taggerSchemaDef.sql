PRAGMA foreign_keys = on;
CREATE TABLE IF NOT EXISTS "Descriptor" (
  "id" INTEGER PRIMARY KEY NOT NULL,
  "descriptor" VARCHAR NOT NULL,
  CONSTRAINT "DescriptorName" UNIQUE("descriptor") ON CONFLICT IGNORE
);
CREATE TABLE IF NOT EXISTS  "File" (
  "id" INTEGER PRIMARY KEY NOT NULL,
  "filePath" VARCHAR NOT NULL,
  CONSTRAINT "FilePath" UNIQUE("filePath") ON CONFLICT IGNORE
);
CREATE TABLE IF NOT EXISTS  "MetaDescriptor" (
  "metaDescriptorId" INTEGER NOT NULL,
  "infraDescriptorId" INTEGER NOT NULL,
  CONSTRAINT "InfraRelationUnique" UNIQUE ("infraDescriptorId") ON CONFLICT REPLACE,
  FOREIGN KEY("metaDescriptorId") REFERENCES "Descriptor"("id") ON DELETE CASCADE,
  FOREIGN KEY("infraDescriptorId") REFERENCES "Descriptor"("id") ON DELETE CASCADE
);
CREATE TABLE IF NOT EXISTS  "Tag" (
  "id" INTEGER PRIMARY KEY NOT NULL,
  "fileTagId" INTEGER NOT NULL,
  "descriptorTagId" INTEGER NOT NULL,
  "subTagOfId" INTEGER,
  CONSTRAINT "TagKey" UNIQUE("fileTagId", "descriptorTagId", "subTagOfId") 
    ON CONFLICT IGNORE,
  FOREIGN KEY("fileTagId") REFERENCES "File"("id") ON DELETE CASCADE,
  FOREIGN KEY("descriptorTagId") REFERENCES "Descriptor"("id") ON DELETE CASCADE
);
CREATE TABLE IF NOT EXISTS "Representative" (
  "repFileId" INTEGER NOT NULL,
  "repDescriptorId" INTEGER NOT NULL,
  "description" TEXT,
  FOREIGN KEY("repFileId") REFERENCES "File"("id") ON DELETE CASCADE,
  FOREIGN KEY("repDescriptorId") REFERENCES "Descriptor"("id") ON DELETE CASCADE,
  CONSTRAINT "repDescriptorUnique" UNIQUE("repDescriptorId") ON CONFLICT REPLACE
);
INSERT INTO Descriptor (descriptor) VALUES ('#ALL#'), ('#META#'),  ('#UNRELATED#');
-- relate #META# and #UNRELATED# to #ALL#
INSERT INTO MetaDescriptor (metaDescriptorId, infraDescriptorId)
  SELECT
    (SELECT id FROM Descriptor WHERE descriptor = '#ALL#'),
    id
  FROM Descriptor
  WHERE descriptor IN ('#META#','#UNRELATED#');