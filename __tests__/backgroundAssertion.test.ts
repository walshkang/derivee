import {
  beginBackgroundTask,
  endBackgroundTask,
  withBackgroundTask,
} from '../modules/expo-background-assertion';
import ExpoBackgroundAssertionModule from '../modules/expo-background-assertion/src/ExpoBackgroundAssertionModule';

describe('Expo Background Assertion Module', () => {
  let beginSpy: jest.SpyInstance;
  let endSpy: jest.SpyInstance;

  beforeEach(() => {
    jest.clearAllMocks();
    beginSpy = jest.spyOn(ExpoBackgroundAssertionModule, 'beginBackgroundTask').mockReturnValue(101);
    endSpy = jest.spyOn(ExpoBackgroundAssertionModule, 'endBackgroundTask').mockImplementation(() => {});
  });

  afterEach(() => {
    beginSpy.mockRestore();
    endSpy.mockRestore();
  });

  it('should begin and end background tasks successfully', () => {
    const taskId = beginBackgroundTask('TestTask');
    expect(taskId).toBe(101);
    expect(beginSpy).toHaveBeenCalledWith('TestTask');

    endBackgroundTask(taskId);
    expect(endSpy).toHaveBeenCalledWith(101);
  });

  it('should execute withBackgroundTask and release assertion on completion', async () => {
    const mockTask = jest.fn().mockResolvedValue('success');

    const result = await withBackgroundTask('AsyncTestTask', mockTask);

    expect(result).toBe('success');
    expect(mockTask).toHaveBeenCalledTimes(1);
    expect(beginSpy).toHaveBeenCalledWith('AsyncTestTask');
    expect(endSpy).toHaveBeenCalledWith(101);
  });

  it('should ensure endBackgroundTask is called even if task throws an error', async () => {
    const failingTask = jest.fn().mockRejectedValue(new Error('Background operation failed'));

    await expect(withBackgroundTask('FailingTask', failingTask)).rejects.toThrow('Background operation failed');

    expect(beginSpy).toHaveBeenCalledWith('FailingTask');
    expect(endSpy).toHaveBeenCalledWith(101);
  });
});
