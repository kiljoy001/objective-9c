package main

import (
	"fmt"
	"log"
	"os"

	"github.com/knusbaum/go9p"
	"github.com/knusbaum/go9p/fs"
	"github.com/knusbaum/go9p/proto"
)

/* 
 * o9pkg.go - High-speed Go-based 9P Installer 
 * Dynamically serves files from disk to prevent sync issues.
 */

var instScript = `#!/bin/rc
echo 'Installing o9 Toolchain (Go-powered)...'
cp /n/o9/bin/o9c /bin/o9c
cp /n/o9/include/o9.h /sys/include/o9.h
cp /n/o9/lib/libo9.a /sys/lib/libo9.a
chmod +x /bin/o9c
echo 'o9 Installation Complete.'
`

type DiskFile struct {
	*fs.BaseFile
	path string
}

func (f *DiskFile) Read(fid *fs.FFid, offset uint64, count uint32) ([]byte, error) {
	data, err := os.ReadFile(f.path)
	if err != nil {
		return nil, err
	}
	if offset >= uint64(len(data)) {
		return nil, nil
	}
	end := offset + uint64(count)
	if end > uint64(len(data)) {
		end = uint64(len(data))
	}
	return data[offset:end], nil
}

func main() {
	user := os.Getenv("USER")
	if user == "" {
		user = "scott"
	}

	fsys, root := fs.NewFS("o9", user, 0755)
	
	root.AddChild(fs.NewStaticFile(fsys.NewStat("install", user, user, 0444), []byte(instScript)))
	
	binDir := fs.NewStaticDir(fsys.NewStat("bin", user, user, 0755|proto.DMDIR))
	root.AddChild(binDir)
	
	incDir := fs.NewStaticDir(fsys.NewStat("include", user, user, 0755|proto.DMDIR))
	root.AddChild(incDir)
	
	libDir := fs.NewStaticDir(fsys.NewStat("lib", user, user, 0755|proto.DMDIR))
	root.AddChild(libDir)

	srcDir := fs.NewStaticDir(fsys.NewStat("src", user, user, 0755|proto.DMDIR))
	root.AddChild(srcDir)

	cmdDir := fs.NewStaticDir(fsys.NewStat("cmd", user, user, 0755|proto.DMDIR))
	srcDir.AddChild(cmdDir)

	o9cSrcDir := fs.NewStaticDir(fsys.NewStat("o9c", user, user, 0755|proto.DMDIR))
	cmdDir.AddChild(o9cSrcDir)

	// Dynamically serve files from disk
	addDiskFile(fsys, binDir, "o9c", "o9c/o9c", user)
	addDiskFile(fsys, incDir, "o9.h", "o9.h", user)
	addDiskFile(fsys, libDir, "libo9.a", "libo9.a", user)
	addDiskFile(fsys, o9cSrcDir, "o9.y", "o9c/o9.y", user)

	fmt.Println("o9 Go-Powered Installer listening on :9009 (Dynamic Sync)")
	log.Fatal(go9p.Serve("0.0.0.0:9009", fsys.Server()))
}

func addDiskFile(fsys *fs.FS, parent *fs.StaticDir, name, path, user string) {
	df := &DiskFile{
		path: path,
	}
	df.BaseFile = fs.NewBaseFile(fsys.NewStat(name, user, user, 0444))
	parent.AddChild(df)
}
