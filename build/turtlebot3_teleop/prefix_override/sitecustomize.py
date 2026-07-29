import sys
if sys.prefix == '/usr':
    sys.real_prefix = sys.prefix
    sys.prefix = sys.exec_prefix = '/workspaces/UON-CS-robotlab-simulation-container/install/turtlebot3_teleop'
