/*
 Copyright 2015 Spotify AB

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

#import "Config.h"
#import "ViewController.h"
#import <Spotify/SPTDiskCache.h>

@interface ViewController () <SPTAudioStreamingDelegate>

@property (weak, nonatomic) IBOutlet UILabel *titleLabel;
@property (weak, nonatomic) IBOutlet UILabel *albumLabel;
@property (weak, nonatomic) IBOutlet UILabel *artistLabel;
@property (weak, nonatomic) IBOutlet UIImageView *coverView;
@property (weak, nonatomic) IBOutlet UIImageView *coverView2;
@property (weak, nonatomic) IBOutlet UIActivityIndicatorView *spinner;

@property (nonatomic, strong) SPTAudioStreamingController *player;
@property (nonatomic, strong) SPTPlaybackState* playbackState;

@property IBOutlet UIButton* nextButton;
@property IBOutlet UIButton* prevButton;

@end

@implementation ViewController

-(void)viewDidLoad {
    [super viewDidLoad];
    self.titleLabel.text = @"Nothing Playing";
    self.albumLabel.text = @"";
    self.artistLabel.text = @"";
}

- (BOOL)prefersStatusBarHidden {
    return YES;
}

#pragma mark - Actions

-(IBAction)rewind:(id)sender {
    [self.player skipPrevious:nil];
}

-(IBAction)playPause:(id)sender {
    [self.player setIsPlaying:!self.player.isPlaying callback:^(NSError *error) {
        NSLog(@"Play pause: %@", error);
    }];
}

- (IBAction)playURI:(id)sender {
    NSURL *url = [NSURL URLWithString:@"spotify:track:50YjprT4gkGLhHpkOM6p5o"];
    [self.player playURI:url startingWithIndex:10 callback:^(NSError *error) {
        if (error != nil) {
            NSLog(@"*** failed to play: %@", error);
            return;
        }
    }];
}

- (IBAction)hitQueueURI:(id)sender {
    NSURL *url = [NSURL URLWithString:@"spotify:track:4TeHKwS2FBGCW3YGyrlbyl"];
    [self.player queueURI:url callback:^(NSError *error) {
        NSLog(@"quereURI error: %@", error);
        NSURL *url2 = [NSURL URLWithString:@"spotify:track:5Iud0Q7wJrTTHWgxXMAmUi"];
        [self.player queueURI:url2 callback:^(NSError *error) {
            NSLog(@"quereURI2 error: %@", error);
        }];
    }];
    

}

-(IBAction)fastForward:(id)sender {
    [self.player skipNext:nil];
}

- (IBAction)logoutClicked:(id)sender {
    if (self.player) {
        [self.player logout];
    } else {
        [self.navigationController popViewControllerAnimated:YES];
    }
}

#pragma mark - Logic


- (UIImage *)applyBlurOnImage: (UIImage *)imageToBlur
                   withRadius: (CGFloat)blurRadius {

    CIImage *originalImage = [CIImage imageWithCGImage: imageToBlur.CGImage];
    CIFilter *filter = [CIFilter filterWithName: @"CIGaussianBlur"
                                  keysAndValues: kCIInputImageKey, originalImage,
                        @"inputRadius", @(blurRadius), nil];

    CIImage *outputImage = filter.outputImage;
    CIContext *context = [CIContext contextWithOptions:nil];

    CGImageRef outImage = [context createCGImage: outputImage
                                        fromRect: [outputImage extent]];

    UIImage *ret = [UIImage imageWithCGImage: outImage];

    CGImageRelease(outImage);

    return ret;
}

-(void)updateUI {
    SPTAuth *auth = [SPTAuth defaultInstance];

    if (self.playbackState.currentTrack == nil) {
        self.coverView.image = nil;
        self.coverView2.image = nil;
        return;
    }
    
    [self.spinner startAnimating];

    self.nextButton.enabled = self.playbackState.nextTrack != nil;
    self.prevButton.enabled = self.playbackState.prevTrack != nil;

    [SPTTrack trackWithURI: [NSURL URLWithString:self.playbackState.currentTrack.uri]
                   session:auth.session
                  callback:^(NSError *error, SPTTrack *track) {

                      self.titleLabel.text = track.name;
                      self.albumLabel.text = track.album.name;

                      SPTPartialArtist *artist = [track.artists objectAtIndex:0];
                      self.artistLabel.text = artist.name;

                      NSURL *imageURL = track.album.largestCover.imageURL;
                      if (imageURL == nil) {
                          NSLog(@"Album %@ doesn't have any images!", track.album);
                          self.coverView.image = nil;
                          self.coverView2.image = nil;
                          return;
                      }

                      // Pop over to a background queue to load the image over the network.
                      dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
                          NSError *error = nil;
                          UIImage *image = nil;
                          NSData *imageData = [NSData dataWithContentsOfURL:imageURL options:0 error:&error];

                          if (imageData != nil) {
                              image = [UIImage imageWithData:imageData];
                          }


                          // …and back to the main queue to display the image.
                          dispatch_async(dispatch_get_main_queue(), ^{
                              [self.spinner stopAnimating];
                              self.coverView.image = image;
                              if (image == nil) {
                                  NSLog(@"Couldn't load cover image with error: %@", error);
                                  return;
                              }
                          });
                          
                          // Also generate a blurry version for the background
                          UIImage *blurred = [self applyBlurOnImage:image withRadius:10.0f];
                          dispatch_async(dispatch_get_main_queue(), ^{
                              self.coverView2.image = blurred;
                          });
                      });

    }];
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    [self handleNewSession];
}

-(void)handleNewSession {
    SPTAuth *auth = [SPTAuth defaultInstance];

    if (self.player == nil) {
        NSError *error = nil;
        self.player = [SPTAudioStreamingController sharedInstance];
        if ([self.player startWithClientId:auth.clientID audioController:nil allowCaching:YES error:&error]) {
            self.player.delegate = self;
            self.player.playbackDelegate = self;
            self.player.diskCache = [[SPTDiskCache alloc] initWithCapacity:1024 * 1024 * 64];
            [self.player loginWithAccessToken:auth.session.accessToken];
        } else {
            self.player = nil;
            UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Error init" message:[error description] preferredStyle:UIAlertControllerStyleAlert];
            [alert addAction:[UIAlertAction actionWithTitle:@"Ok" style:UIAlertActionStyleDefault handler:nil]];
            [self presentViewController:alert animated:YES completion:nil];
            [self audioStreamingDidLogout:nil];
        }
    }   
}

#pragma mark - Track Player Delegates

- (void)audioStreaming:(SPTAudioStreamingController *)audioStreaming didReceiveMessage:(NSString *)message {
    UIAlertView *alertView = [[UIAlertView alloc] initWithTitle:@"Message from Spotify"
                                                        message:message
                                                       delegate:nil
                                              cancelButtonTitle:@"OK"
                                              otherButtonTitles:nil];
    [alertView show];
}

- (void)audioStreaming:(SPTAudioStreamingController *)audioStreaming didFailToPlayTrack:(NSURL *)trackUri {
    NSLog(@"failed to play track: %@", trackUri);
}


- (void)audioStreaming:(SPTAudioStreamingController *)audioStreaming didChangePlaybackStatus:(BOOL)isPlaying {
    NSLog(@"is playing = %d", isPlaying);
}

-(void)audioStreaming:(SPTAudioStreamingController *)audioStreaming didChangePlaybackState:(SPTPlaybackState *)playbackState {
    self.playbackState = playbackState;
    NSLog(@"PS %@, %@, %@", playbackState.prevTrack, playbackState.currentTrack, playbackState.nextTrack);
    [self updateUI];
}

- (void)audioStreamingDidLogout:(SPTAudioStreamingController *)audioStreaming {
    NSError *error = nil;
    if (![self.player stopWithError:&error]) {
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Error deinit" message:[error description] preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"Ok" style:UIAlertActionStyleDefault handler:nil]];
        [self presentViewController:alert animated:YES completion:nil];
        [self audioStreamingDidLogout:nil];
    }
    [SPTAuth defaultInstance].session = nil;
    [self.navigationController popViewControllerAnimated:YES];
}

- (void)audioStreaming:(SPTAudioStreamingController *)audioStreaming didEncounterError:(NSError *)error {
    if (error != nil) {
        NSLog(@"*** Playback got error: %@", error);
        return;
    }
}

- (void)audioStreamingDidLogin:(SPTAudioStreamingController *)audioStreaming {

    [self updateUI];
}
@end
