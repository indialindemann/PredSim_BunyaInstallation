# PredSim_BunyaInstallation
Files that install PredSim and all its dependencies onto UQ's HPC (Bunya)

Please follow the instructions below to install PredSim onto Bunya. There are some manual steps that have to happen before you run the install shell script:

1. Download this repo files and copy the files onto bunya using scp command
   example:
   
   scp -r "C:\Users\YOURNAME\Downloads\PredSim_BunyaInstallation" YOURNAME@bunya.rcc.uq.edu.au:/home/YOURNAME/PredSim_BunyaInstallation
   
3. cd into the PredSim_BunyaInstallation folder, and run the following command
   
   chmod +x predsim_install.sh
   
4. Run the following commands
   
   cd $HOME
   
   mkdir -p $HOME/predsim_install/opensim_win

   mkdir -p $HOME/deps/opensim-install

   cd $HOME/predsim_install/opensim_win

   wget https://www.7-zip.org/a/7z2600-linux-x64.tar.xz

   tar xf 7z2600-linux-x64.tar.xz

5. Download the opensim installer from here: https://simtk.org/frs/?group_id=91
   Go down to previous releases and download opensim 4.4
6. Then copy opensim onto bunya. On your normal terminal (**not in bunya**) run the following command:
   
    scp "C:\Users\YOURNAME\Downloads\OpenSim-4.4-win64.exe" YOURNAME@bunya.rcc.uq.edu.au:/home/YOURNAME/predsim_install/opensim_win
   
8. Back to bunya. run the following commands
   
   ./7zz x OpenSim-4.4-win64.exe
   
   cp -r Geometry/ ~/deps/opensim-install/
   
9. Now add the ssh key from bunya to your github account and ask India to add your github account to the relevant version of PredSim. See https://docs.github.com/en/authentication/connecting-to-github-with-ssh/generating-a-new-ssh-key-and-adding-it-to-the-ssh-agent
10. Then, go into the predsim_install folder in Bunya then run
    
    mv ../PredSim_BunyaInstallation/predsim_install.sh
    
12. Finally, run  ./predsim_install.sh
