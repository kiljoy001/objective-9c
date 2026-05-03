package main

import (
	"bytes"
	"os/exec"
	"strings"
	"testing"
)

func TestTranspilation(t *testing.T) {
	// Sample O9 code
	input := "class Test { int64 val; }"
	
	cmd := exec.Command("./o9c")
	cmd.Stdin = strings.NewReader(input)
	
	var out bytes.Buffer
	cmd.Stdout = &out
	
	err := cmd.Run()
	if err != nil {
		t.Fatalf("o9c failed: %v", err)
	}
	
	output := out.String()
	
	// Check for mandatory Plan 9 headers
	if !strings.Contains(output, "#include <u.h>") {
		t.Error("Missing <u.h>")
	}
	if !strings.Contains(output, "#include <libc.h>") {
		t.Error("Missing <libc.h>")
	}
	if !strings.Contains(output, "#include <fcall.h>") {
		t.Error("Missing <fcall.h>")
	}
	if !strings.Contains(output, "#include <9p.h>") {
		t.Error("Missing <9p.h>")
	}
	
	// Check for class structures
	if !strings.Contains(output, "struct Test_State") {
		t.Error("Missing state struct")
	}
	if !strings.Contains(output, "Srv o9srv_Test") {
		t.Error("Missing Srv symbol")
	}
}
