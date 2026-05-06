package main

import (
	"testing"
)

func TestParseCounter(t *testing.T) {
	input := []byte(`class Counter {
		int64 val;
		func (Counter *c) inc() void {
			val = val + 1;
		}
	}`)
	_ = input
}
