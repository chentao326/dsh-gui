#!/bin/bash
# Fake dsh CLI for integration testing: boots, prints the URL line, stays alive.
echo "fake dsh booting (pid $$)"
sleep 1
echo "dsh web: http://127.0.0.1:39999"
sleep 300
