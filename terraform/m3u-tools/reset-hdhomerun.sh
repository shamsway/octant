#!/bin/bash
hdhomerun_config FFFFFFFF set /tuner0/lockkey force
hdhomerun_config FFFFFFFF set /tuner0/channel none
hdhomerun_config FFFFFFFF get /tuner0/status
hdhomerun_config FFFFFFFF set /tuner1/lockkey force
hdhomerun_config FFFFFFFF set /tuner1/channel none
hdhomerun_config FFFFFFFF get /tuner1/status