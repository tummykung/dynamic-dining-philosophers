osascript<<EOF
tell application "Terminal"
    activate
        tell application "System Events"
            keystroke "t" using command down # new tab
            keystroke "ssh cpruce@arden.cs.hmc.edu"
            key code 36 # press enter
            keystroke "cd dynamic-dining-philosophers/src/" 
            key code 36 # press enter
            keystroke "erl -noshell -run philosopher main a"
            key code 36 # press enter

            keystroke "t" using command down # new tab
            keystroke "ssh cpruce@clover.cs.hmc.edu"
            key code 36 # press enter
            keystroke "cd dynamic-dining-philosophers/src/"
            key code 36 # press enter
            keystroke "sleep 2" # allow time for a@arden to start
            key code 36 # press enter
            keystroke "erl -noshell -run philosopher main b a@arden"
            key code 36 # press enter

            keystroke "t" using  command down # new tab
            keystroke "ssh cpruce@flax.cs.hmc.edu"
            key code 36 # press enter
            keystroke "cd dynamic-dining-philosophers/src/" 
            key code 36 # press enter
            keystroke "sleep 4" # allow time for a@arden and b@clover
            key code 36 # press enter
            keystroke "erl -noshell -run philosopher main  c a@arden b@clover"            key code 36 # press  enter

            keystroke "t" using command down # new tab                                  keystroke "ssh cpruce@dittany.cs.hmc.edu"
            key code 36 # press enter
            keystroke "cd dynamic-dining-philosophers/src/
            key code 36 #  press enter
            keystroke "sleep 6" # allow time for a@arden, b@clover, and c@flax
            key code 36 # press enter
            keystroke "erl -noshell -run philosopher main d a@arden b@clover c@flax"
            key code 36 # press enter                                                   end tell
        end tell                                                                EOF
