//
//  AspectsSwift.swift
//  pip_flutter
//
//  Created by vicky Leu on 2022/12/5.
//

import Foundation

public extension NSObject {

    func aspect_hook(
        selector: Selector,
        options: AspectOptions,
        usingBlock: @escaping(AspectInfo) -> Void)  throws -> AspectToken
    {
        let wrappedBlock: @convention(block) (AspectInfo) -> Void = { aspectInfo in
            usingBlock(aspectInfo)
        }

        let wrappedObject: AnyObject = unsafeBitCast(wrappedBlock, to: AnyObject.self)
        do {
          return  try aspect_hook(selector, with: options, usingBlock: wrappedObject)
        } catch {
            throw error
        }
    }

    func aspect_hook<Arg1>(
        selector: Selector,
        options: AspectOptions,
        usingBlock: @escaping(AspectInfo, Arg1) -> Void) throws  -> AspectToken
    {
        let wrappedBlock: @convention(block) (AspectInfo) -> Void = { aspectInfo in
            guard aspectInfo.arguments()?.count == 1,
                let arg1 = aspectInfo.arguments()[0] as? Arg1 else { return }
            usingBlock(aspectInfo, arg1)
        }

        let wrappedObject: AnyObject = unsafeBitCast(wrappedBlock, to: AnyObject.self)
        do {
           return try aspect_hook(selector, with: options, usingBlock: wrappedObject)
        } catch {
            throw error
        }
    }

    func aspect_hook<Arg1, Arg2>(
        selector: Selector,
        options: AspectOptions,
        usingBlock: @escaping(AspectInfo, Arg1, Arg2) -> Void) throws  -> AspectToken
    {
        let wrappedBlock: @convention(block) (AspectInfo) -> Void = { aspectInfo in
            guard aspectInfo.arguments()?.count == 2,
                let arg1 = aspectInfo.arguments()[0] as? Arg1,
                let arg2 = aspectInfo.arguments()[1] as? Arg2 else { return }
            usingBlock(aspectInfo, arg1, arg2)
        }

        let wrappedObject: AnyObject = unsafeBitCast(wrappedBlock, to: AnyObject.self)
        do {
           return try aspect_hook(selector, with: options, usingBlock: wrappedObject)
        } catch {
            throw error
        }
    }

    func aspect_hook<Arg1, Arg2, Arg3>(
        selector: Selector,
        options: AspectOptions,
        usingBlock: @escaping(AspectInfo, Arg1, Arg2, Arg3) -> Void) throws  -> AspectToken
    {
        let wrappedBlock: @convention(block) (AspectInfo) -> Void = { aspectInfo in
            guard aspectInfo.arguments()?.count == 3,
                let arg1 = aspectInfo.arguments()[0] as? Arg1,
                let arg2 = aspectInfo.arguments()[1] as? Arg2,
                let arg3 = aspectInfo.arguments()[2] as? Arg3 else { return }
            usingBlock(aspectInfo, arg1, arg2, arg3)
        }

        let wrappedObject: AnyObject = unsafeBitCast(wrappedBlock, to: AnyObject.self)
        do {
           return try aspect_hook(selector, with: options, usingBlock: wrappedObject)
        } catch {
            throw error
        }
    }

    func aspect_hook<Arg1, Arg2, Arg3, Arg4>(
        selector: Selector,
        options: AspectOptions,
        usingBlock: @escaping(AspectInfo, Arg1, Arg2, Arg3, Arg4) -> Void) throws  -> AspectToken
    {
        let wrappedBlock: @convention(block) (AspectInfo) -> Void = { aspectInfo in
            guard aspectInfo.arguments()?.count == 4,
                let arg1 = aspectInfo.arguments()[0] as? Arg1,
                let arg2 = aspectInfo.arguments()[1] as? Arg2,
                let arg3 = aspectInfo.arguments()[2] as? Arg3,
                let arg4 = aspectInfo.arguments()[3] as? Arg4 else { return  }
            usingBlock(aspectInfo, arg1, arg2, arg3, arg4)
        }

        let wrappedObject: AnyObject = unsafeBitCast(wrappedBlock, to: AnyObject.self)
        do {
          return  try aspect_hook(selector, with: options, usingBlock: wrappedObject)
        } catch {
            throw error
        }
    }

    func aspect_hook<Arg1, Arg2, Arg3, Arg4, Arg5>(
        selector: Selector,
        options: AspectOptions,
        usingBlock: @escaping(AspectInfo, Arg1, Arg2, Arg3, Arg4, Arg5) -> Void) throws  -> AspectToken
    {
        let wrappedBlock: @convention(block) (AspectInfo) -> Void = { aspectInfo in
            guard aspectInfo.arguments()?.count == 5,
                let arg1 = aspectInfo.arguments()[0] as? Arg1,
                let arg2 = aspectInfo.arguments()[1] as? Arg2,
                let arg3 = aspectInfo.arguments()[2] as? Arg3,
                let arg4 = aspectInfo.arguments()[3] as? Arg4,
                let arg5 = aspectInfo.arguments()[4] as? Arg5 else {
                    return
            }
            usingBlock(aspectInfo, arg1, arg2, arg3, arg4, arg5)
        }

        let wrappedObject: AnyObject = unsafeBitCast(wrappedBlock, to: AnyObject.self)
        do {
           return try aspect_hook(selector, with: options, usingBlock: wrappedObject)
        } catch {
            throw error
        }
    }

    func aspect_hook<Arg1, Arg2, Arg3, Arg4, Arg5, Arg6>(
        selector: Selector,
        options: AspectOptions,
        usingBlock: @escaping(AspectInfo, Arg1, Arg2, Arg3, Arg4, Arg5, Arg6) -> Void) throws  -> AspectToken
    {
        let wrappedBlock: @convention(block) (AspectInfo) -> Void = { aspectInfo in
            guard aspectInfo.arguments()?.count == 6,
                let arg1 = aspectInfo.arguments()[0] as? Arg1,
                let arg2 = aspectInfo.arguments()[1] as? Arg2,
                let arg3 = aspectInfo.arguments()[2] as? Arg3,
                let arg4 = aspectInfo.arguments()[3] as? Arg4,
                let arg5 = aspectInfo.arguments()[4] as? Arg5,
                let arg6 = aspectInfo.arguments()[5] as? Arg6 else {
                    return
            }
            usingBlock(aspectInfo, arg1, arg2, arg3, arg4, arg5, arg6)
        }

        let wrappedObject: AnyObject = unsafeBitCast(wrappedBlock, to: AnyObject.self)
        do {
           return try aspect_hook(selector, with: options, usingBlock: wrappedObject)
        } catch {
            throw error
        }
    }


    func aspect_hook<Arg1, Arg2, Arg3, Arg4, Arg5, Arg6, Arg7>(
        selector: Selector,
        options: AspectOptions,
        usingBlock: @escaping(AspectInfo, Arg1, Arg2, Arg3, Arg4, Arg5, Arg6, Arg7) -> Void) throws   -> AspectToken
    {
        let wrappedBlock: @convention(block) (AspectInfo) -> Void = { aspectInfo in
            guard aspectInfo.arguments()?.count == 7,
                let arg1 = aspectInfo.arguments()[0] as? Arg1,
                let arg2 = aspectInfo.arguments()[1] as? Arg2,
                let arg3 = aspectInfo.arguments()[2] as? Arg3,
                let arg4 = aspectInfo.arguments()[3] as? Arg4,
                let arg5 = aspectInfo.arguments()[4] as? Arg5,
                let arg6 = aspectInfo.arguments()[5] as? Arg6,
                let arg7 = aspectInfo.arguments()[6] as? Arg7 else {
                    return
            }
            usingBlock(aspectInfo, arg1, arg2, arg3, arg4, arg5, arg6, arg7)
        }

        let wrappedObject: AnyObject = unsafeBitCast(wrappedBlock, to: AnyObject.self)
        do {
           return try aspect_hook(selector, with: options, usingBlock: wrappedObject)
        } catch {
            throw error
        }
    }
}

public extension NSObject {

    class func aspect_hook(
        selector: Selector,
        options: AspectOptions,
        usingBlock: @escaping(AspectInfo) -> Void) throws   -> AspectToken
    {
        let wrappedBlock: @convention(block) (AspectInfo) -> Void = { aspectInfo in
            usingBlock(aspectInfo)
        }

        let wrappedObject: AnyObject = unsafeBitCast(wrappedBlock, to: AnyObject.self)
        do {
           return try aspect_hook(selector, with: options, usingBlock: wrappedObject)
        } catch {
            throw error
        }
    }

    class func aspect_hook<Arg1>(
        selector: Selector,
        options: AspectOptions,
        usingBlock: @escaping(AspectInfo, Arg1) -> Void) throws   -> AspectToken
    {
        let wrappedBlock: @convention(block) (AspectInfo) -> Void = { aspectInfo in
            guard aspectInfo.arguments()?.count == 1,
                let arg1 = aspectInfo.arguments()[0] as? Arg1 else { return }
            usingBlock(aspectInfo, arg1)
        }

        let wrappedObject: AnyObject = unsafeBitCast(wrappedBlock, to: AnyObject.self)
        do {
           return try aspect_hook(selector, with: options, usingBlock: wrappedObject)
        } catch {
            throw error
        }
    }

    class func aspect_hook<Arg1, Arg2>(
        selector: Selector,
        options: AspectOptions,
        usingBlock: @escaping(AspectInfo, Arg1, Arg2) -> Void) throws   -> AspectToken
    {
        let wrappedBlock: @convention(block) (AspectInfo) -> Void = { aspectInfo in
            guard aspectInfo.arguments()?.count == 2,
                let arg1 = aspectInfo.arguments()[0] as? Arg1,
                let arg2 = aspectInfo.arguments()[1] as? Arg2 else { return }
            usingBlock(aspectInfo, arg1, arg2)
        }

        let wrappedObject: AnyObject = unsafeBitCast(wrappedBlock, to: AnyObject.self)
        do {
          return  try aspect_hook(selector, with: options, usingBlock: wrappedObject)
        } catch {
            throw error
        }
    }

    class func aspect_hook<Arg1, Arg2, Arg3>(
        selector: Selector,
        options: AspectOptions,
        usingBlock: @escaping(AspectInfo, Arg1, Arg2, Arg3) -> Void) throws   -> AspectToken
    {
        let wrappedBlock: @convention(block) (AspectInfo) -> Void = { aspectInfo in
            guard aspectInfo.arguments()?.count == 3,
                let arg1 = aspectInfo.arguments()[0] as? Arg1,
                let arg2 = aspectInfo.arguments()[1] as? Arg2,
                let arg3 = aspectInfo.arguments()[2] as? Arg3 else { return }
            usingBlock(aspectInfo, arg1, arg2, arg3)
        }

        let wrappedObject: AnyObject = unsafeBitCast(wrappedBlock, to: AnyObject.self)
        do {
          return  try aspect_hook(selector, with: options, usingBlock: wrappedObject)
        } catch {
            throw error
        }
    }

    class func aspect_hook<Arg1, Arg2, Arg3, Arg4>(
        selector: Selector,
        options: AspectOptions,
        usingBlock: @escaping(AspectInfo, Arg1, Arg2, Arg3, Arg4) -> Void) throws   -> AspectToken
    {
        let wrappedBlock: @convention(block) (AspectInfo) -> Void = { aspectInfo in
            guard aspectInfo.arguments()?.count == 4,
                let arg1 = aspectInfo.arguments()[0] as? Arg1,
                let arg2 = aspectInfo.arguments()[1] as? Arg2,
                let arg3 = aspectInfo.arguments()[2] as? Arg3,
                let arg4 = aspectInfo.arguments()[3] as? Arg4 else { return }
            usingBlock(aspectInfo, arg1, arg2, arg3, arg4)
        }

        let wrappedObject: AnyObject = unsafeBitCast(wrappedBlock, to: AnyObject.self)
        do {
          return  try aspect_hook(selector, with: options, usingBlock: wrappedObject)
        } catch {
            throw error
        }
    }

    class func aspect_hook<Arg1, Arg2, Arg3, Arg4, Arg5>(
        selector: Selector,
        options: AspectOptions,
        usingBlock: @escaping(AspectInfo, Arg1, Arg2, Arg3, Arg4, Arg5) -> Void) throws   -> AspectToken
    {
        let wrappedBlock: @convention(block) (AspectInfo) -> Void = { aspectInfo in
            guard aspectInfo.arguments()?.count == 5,
                let arg1 = aspectInfo.arguments()[0] as? Arg1,
                let arg2 = aspectInfo.arguments()[1] as? Arg2,
                let arg3 = aspectInfo.arguments()[2] as? Arg3,
                let arg4 = aspectInfo.arguments()[3] as? Arg4,
                let arg5 = aspectInfo.arguments()[4] as? Arg5 else {
                    return
            }
            usingBlock(aspectInfo, arg1, arg2, arg3, arg4, arg5)
        }

        let wrappedObject: AnyObject = unsafeBitCast(wrappedBlock, to: AnyObject.self)
        do {
           return try aspect_hook(selector, with: options, usingBlock: wrappedObject)
        } catch {
            throw error
        }
    }

    class func aspect_hook<Arg1, Arg2, Arg3, Arg4, Arg5, Arg6>(
        selector: Selector,
        options: AspectOptions,
        usingBlock: @escaping(AspectInfo, Arg1, Arg2, Arg3, Arg4, Arg5, Arg6) -> Void) throws   -> AspectToken
    {
        let wrappedBlock: @convention(block) (AspectInfo) -> Void = { aspectInfo in
            guard aspectInfo.arguments()?.count == 6,
                let arg1 = aspectInfo.arguments()[0] as? Arg1,
                let arg2 = aspectInfo.arguments()[1] as? Arg2,
                let arg3 = aspectInfo.arguments()[2] as? Arg3,
                let arg4 = aspectInfo.arguments()[3] as? Arg4,
                let arg5 = aspectInfo.arguments()[4] as? Arg5,
                let arg6 = aspectInfo.arguments()[5] as? Arg6 else {
                    return
            }
            usingBlock(aspectInfo, arg1, arg2, arg3, arg4, arg5, arg6)
        }

        let wrappedObject: AnyObject = unsafeBitCast(wrappedBlock, to: AnyObject.self)
        do {
           return try aspect_hook(selector, with: options, usingBlock: wrappedObject)
        } catch {
            throw error
        }
    }

    class func aspect_hook<Arg1, Arg2, Arg3, Arg4, Arg5, Arg6, Arg7>(
        selector: Selector,
        options: AspectOptions,
        usingBlock: @escaping(AspectInfo, Arg1, Arg2, Arg3, Arg4, Arg5, Arg6, Arg7) -> Void) throws   -> AspectToken
    {
        let wrappedBlock: @convention(block) (AspectInfo) -> Void = { aspectInfo in
            guard aspectInfo.arguments()?.count == 7,
                let arg1 = aspectInfo.arguments()[0] as? Arg1,
                let arg2 = aspectInfo.arguments()[1] as? Arg2,
                let arg3 = aspectInfo.arguments()[2] as? Arg3,
                let arg4 = aspectInfo.arguments()[3] as? Arg4,
                let arg5 = aspectInfo.arguments()[4] as? Arg5,
                let arg6 = aspectInfo.arguments()[5] as? Arg6,
                let arg7 = aspectInfo.arguments()[6] as? Arg7 else {
                    return
            }
            usingBlock(aspectInfo, arg1, arg2, arg3, arg4, arg5, arg6, arg7)
        }

        let wrappedObject: AnyObject = unsafeBitCast(wrappedBlock, to: AnyObject.self)
        do {
          return  try aspect_hook(selector, with: options, usingBlock: wrappedObject)
        } catch {
            throw error
        }
    }
}
