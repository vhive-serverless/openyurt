/*
Copyright 2021 The OpenYurt Authors.

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
*/

package edgenode

import (
	"testing"
)

func Test_GetPodManifestPath(t *testing.T) {

	path := GetPodManifestPath()
	if path != "/etc/kubernetes/manifests" {
		t.Fatal("get path err: " + path)
	}
}

func Test_GetHostName(t *testing.T) {
	oldOSHost := osHostName
	defer func() {
		osHostName = oldOSHost
	}()

	osHostName = func() (string, error) {
		return "test_host", nil
	}

	tests := []struct {
		name             string
		hostNameOverride string
		expectedHostName string
		expectError      bool
	}{
		{
			"host name with upper case character",
			"TEST_HOST",
			"test_host",
			false,
		},
		{
			"host name with leading space ",
			"    test_host",
			"test_host",
			false,
		},
		{
			"valid host name",
			"test_host",
			"test_host",
			false,
		},
		{
			"invalid host name",
			"    ",
			"",
			true,
		},
		{
			"get from os envs",
			"",
			"test_host",
			false,
		},
	}

	for _, test := range tests {
		test := test
		t.Run(test.name, func(t *testing.T) {
			t.Logf("\tTestCase: %s", test.name)
			{
				hostName, err := GetHostname(test.hostNameOverride)
				if err != nil && !test.expectError {
					t.Errorf("unexpected error: %s", err)
				}
				if err == nil && test.expectError {
					t.Errorf("expected error, got none")
				}
				if test.expectedHostName != hostName {
					t.Errorf("expected output %q, got %q", test.expectedHostName, hostName)
				}
			}
		})
	}
}
